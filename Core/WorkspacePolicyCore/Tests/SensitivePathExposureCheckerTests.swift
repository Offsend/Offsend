import XCTest
@testable import WorkspacePolicyCore

final class IgnorePatternPathMatcherTests: XCTestCase {
    func testGlobLineMatchesWithinSegment() {
        XCTAssertTrue(IgnorePatternPathMatcher.matches(relativePath: "id.pem", ignoreLine: "*.pem"))
        XCTAssertFalse(IgnorePatternPathMatcher.matches(relativePath: "nested/id.pem", ignoreLine: "*.pem"))
    }

    func testGlobLineMatchesRecursivePath() {
        XCTAssertTrue(IgnorePatternPathMatcher.matches(relativePath: "nested/id.pem", ignoreLine: "**/*.pem"))
    }

    func testScopedGlobDoesNotMatchOutsideScope() {
        XCTAssertTrue(IgnorePatternPathMatcher.matches(relativePath: "secrets/a.pem", ignoreLine: "secrets/*.pem"))
        XCTAssertFalse(IgnorePatternPathMatcher.matches(relativePath: "id.pem", ignoreLine: "secrets/*.pem"))
    }

    func testLiteralFilePathMatchesExactly() {
        XCTAssertTrue(IgnorePatternPathMatcher.matches(relativePath: "config/.env", ignoreLine: "config/.env"))
        XCTAssertFalse(IgnorePatternPathMatcher.matches(relativePath: ".env", ignoreLine: "config/.env"))
        XCTAssertFalse(IgnorePatternPathMatcher.matches(relativePath: "config/other/.env", ignoreLine: "config/.env"))
    }

    func testLiteralDirectoryMatchesDescendants() {
        XCTAssertTrue(IgnorePatternPathMatcher.matches(relativePath: ".ssh", ignoreLine: ".ssh"))
        XCTAssertTrue(IgnorePatternPathMatcher.matches(relativePath: ".ssh/id_rsa", ignoreLine: ".ssh"))
        XCTAssertTrue(IgnorePatternPathMatcher.matches(relativePath: ".ssh/nested/id_rsa", ignoreLine: ".ssh/"))
    }

    func testEnvWildcardMatchesVariants() {
        XCTAssertTrue(IgnorePatternPathMatcher.matches(relativePath: ".env", ignoreLine: ".env*"))
        XCTAssertTrue(IgnorePatternPathMatcher.matches(relativePath: ".env.local", ignoreLine: ".env*"))
    }
}

final class SensitivePathMatcherTests: XCTestCase {
    private let pemPattern = AIWorkspaceSensitivePattern(
        id: "pem-files",
        title: "PEM keys",
        acceptedPatterns: ["*.pem", "**/*.pem"],
        severity: .required,
        remediation: ""
    )

    private let envPattern = AIWorkspaceSensitivePattern(
        id: "env-files",
        title: "Environment files",
        acceptedPatterns: [".env", ".env.*", ".env*", "**/.env", "**/.env.*", "**/.env*"],
        severity: .required,
        remediation: ""
    )

    func testMatchesRootPem() {
        XCTAssertEqual(
            SensitivePathMatcher.matchingPattern(relativePath: "id.pem", patterns: [pemPattern])?.id,
            "pem-files"
        )
    }

    func testMatchesNestedPem() {
        XCTAssertEqual(
            SensitivePathMatcher.matchingPattern(relativePath: "certs/id.pem", patterns: [pemPattern])?.id,
            "pem-files"
        )
    }

    func testDoesNotMatchUnrelatedPath() {
        XCTAssertNil(SensitivePathMatcher.matchingPattern(relativePath: "README.md", patterns: [pemPattern]))
    }

    func testMatchesEnvVariants() {
        XCTAssertEqual(
            SensitivePathMatcher.matchingPattern(relativePath: ".env.local", patterns: [envPattern])?.id,
            "env-files"
        )
    }
}

final class SensitivePathExposureCheckerTests: XCTestCase {
    private let checker = SensitivePathExposureChecker()
    private var temporaryDirectories: [URL] = []

    private var defaultSensitivePatterns: [AIWorkspaceSensitivePattern] {
        AIWorkspaceSensitivePattern.defaultPatterns.filter {
            ["pem-files", "env-files", "key-files", "credentials-json"].contains($0.id)
        }
    }

    override func tearDownWithError() throws {
        for url in temporaryDirectories {
            try? FileManager.default.removeItem(at: url)
        }
        temporaryDirectories.removeAll()
        try super.tearDownWithError()
    }

    func testExposedWhenNoIgnoreCoversPath() {
        let finding = checker.exposedFinding(
            relativePath: "certs/server.pem",
            sensitivePatterns: defaultSensitivePatterns,
            ignorePatternsByFile: [:]
        )

        XCTAssertEqual(finding?.relativePath, "certs/server.pem")
        XCTAssertEqual(finding?.pattern.id, "pem-files")
    }

    func testNotExposedWhenGlobalPemIgnorePresent() {
        let ignore: [String: Set<String>] = [
            ".cursorignore": ["*.pem", "**/*.pem"]
        ]

        XCTAssertNil(
            checker.exposedFinding(
                relativePath: "certs/server.pem",
                sensitivePatterns: defaultSensitivePatterns,
                ignorePatternsByFile: ignore
            )
        )
    }

    func testExposedWhenOnlyScopedPemIgnorePresent() {
        let ignore: [String: Set<String>] = [
            ".cursorignore": ["secrets/*.pem"]
        ]

        let rootFinding = checker.exposedFinding(
            relativePath: "id.pem",
            sensitivePatterns: defaultSensitivePatterns,
            ignorePatternsByFile: ignore
        )
        let scopedFinding = checker.exposedFinding(
            relativePath: "secrets/id.pem",
            sensitivePatterns: defaultSensitivePatterns,
            ignorePatternsByFile: ignore
        )

        XCTAssertEqual(rootFinding?.pattern.id, "pem-files")
        XCTAssertNil(scopedFinding)
    }

    func testExposedWhenScopedEnvIgnoreDoesNotCoverRootEnv() {
        let ignore: [String: Set<String>] = [
            ".cursorignore": ["config/.env"]
        ]

        XCTAssertNotNil(
            checker.exposedFinding(
                relativePath: ".env",
                sensitivePatterns: defaultSensitivePatterns,
                ignorePatternsByFile: ignore
            )
        )
        XCTAssertNil(
            checker.exposedFinding(
                relativePath: "config/.env",
                sensitivePatterns: defaultSensitivePatterns,
                ignorePatternsByFile: ignore
            )
        )
    }

    func testEnvExampleIsAllowlisted() {
        XCTAssertNil(
            checker.exposedFinding(
                relativePath: ".env.example",
                sensitivePatterns: defaultSensitivePatterns,
                ignorePatternsByFile: [:]
            )
        )
        XCTAssertFalse(checker.matchesSensitivePattern(relativePath: ".env.example", sensitivePatterns: defaultSensitivePatterns))
    }

    func testTestsDirectoryIsAllowlisted() throws {
        let root = try makeTemporaryDirectory()
        try writeFile("Tests/fixtures/.env", in: root, contents: "x")

        let result = checker.scan(
            directoryURL: root,
            sensitivePatterns: defaultSensitivePatterns,
            ignorePatternsByFile: [:]
        )

        XCTAssertTrue(result.exposedFiles.isEmpty)
    }

    func testPerToolExposureWhenOnlyCopilotIgnoreCoversPem() {
        let unionIgnore: [String: Set<String>] = [
            ".cursorignore": [".env*"],
            ".copilotignore": ["*.pem"]
        ]
        let cursorOnly: [String: Set<String>] = [
            ".cursorignore": [".env*"]
        ]

        XCTAssertNil(
            checker.exposedFinding(
                relativePath: "id.pem",
                sensitivePatterns: defaultSensitivePatterns,
                ignorePatternsByFile: unionIgnore
            )
        )
        XCTAssertNotNil(
            checker.exposedFinding(
                relativePath: "id.pem",
                sensitivePatterns: defaultSensitivePatterns,
                ignorePatternsByFile: cursorOnly
            )
        )
    }

    func testUnionAcrossIgnoreFiles() {
        let ignore: [String: Set<String>] = [
            ".cursorignore": [".env*"],
            ".copilotignore": ["*.pem"]
        ]

        XCTAssertNil(
            checker.exposedFinding(
                relativePath: "id.pem",
                sensitivePatterns: defaultSensitivePatterns,
                ignorePatternsByFile: ignore
            )
        )
        XCTAssertNil(
            checker.exposedFinding(
                relativePath: ".env.local",
                sensitivePatterns: defaultSensitivePatterns,
                ignorePatternsByFile: ignore
            )
        )
    }

    func testScanFindsExposedFilesOnDisk() throws {
        let root = try makeTemporaryDirectory()
        try writeFile("certs/server.pem", in: root, contents: "dummy")
        try writeFile(".cursorignore", in: root, contents: ".env*\n")

        let ignorePatterns = checker.loadIgnorePatterns(
            ignoreFileRelativePaths: [".cursorignore"],
            from: root
        )
        let result = checker.scan(
            directoryURL: root,
            sensitivePatterns: defaultSensitivePatterns,
            ignorePatternsByFile: ignorePatterns
        )

        XCTAssertEqual(result.exposedFiles.map(\.relativePath), ["certs/server.pem"])
        XCTAssertEqual(result.exposedFiles.map(\.pattern.id), ["pem-files"])
    }

    func testScanReturnsEmptyWhenFullyIgnored() throws {
        let root = try makeTemporaryDirectory()
        try writeFile("id.pem", in: root, contents: "dummy")
        try writeFile(".cursorignore", in: root, contents: AIWorkspacePrivacyIgnoreTemplate.contents)

        let ignorePatterns = checker.loadIgnorePatterns(
            ignoreFileRelativePaths: [".cursorignore"],
            from: root
        )
        let result = checker.scan(
            directoryURL: root,
            sensitivePatterns: defaultSensitivePatterns,
            ignorePatternsByFile: ignorePatterns
        )

        XCTAssertTrue(result.exposedFiles.isEmpty)
    }

    func testScanSkipsBuiltInDirectories() throws {
        let root = try makeTemporaryDirectory()
        try writeFile("node_modules/pkg/secret.pem", in: root, contents: "dummy")

        let result = checker.scan(
            directoryURL: root,
            sensitivePatterns: defaultSensitivePatterns,
            ignorePatternsByFile: [:]
        )

        XCTAssertTrue(result.exposedFiles.isEmpty)
    }

    func testScanWithConfigurationUsesExistingIgnoreFiles() throws {
        let root = try makeTemporaryDirectory()
        try writeFile("server.pem", in: root, contents: "dummy")
        try writeFile(".cursorignore", in: root, contents: "*.pem\n")

        let config = AIWorkspacePrivacyAuditConfiguration(
            rules: AIWorkspacePrivacyRule.defaultRules,
            sensitivePatterns: defaultSensitivePatterns
        )
        let result = checker.scan(directoryURL: root, configuration: config)

        XCTAssertTrue(result.exposedFiles.isEmpty)
    }

    func testExposedAmongDedupesPaths() {
        let findings = checker.exposedAmong(
            relativePaths: ["a.pem", "a.pem", "b.pem"],
            sensitivePatterns: defaultSensitivePatterns,
            ignorePatternsByFile: [:]
        )

        XCTAssertEqual(findings.map(\.relativePath), ["a.pem", "b.pem"])
    }

    func testScanTruncatesAtFileLimit() throws {
        let root = try makeTemporaryDirectory()
        for index in 0..<5 {
            try writeFile("file\(index).pem", in: root, contents: "dummy")
        }

        let result = checker.scan(
            directoryURL: root,
            sensitivePatterns: defaultSensitivePatterns,
            ignorePatternsByFile: [:],
            limits: SensitivePathExposureScanLimits(maxFiles: 2, timeLimit: nil)
        )

        if case let .truncated(maxFiles, filesScanned) = result.completion {
            XCTAssertEqual(maxFiles, 2)
            XCTAssertEqual(filesScanned, 2)
        } else {
            XCTFail("Expected truncated completion, got \(result.completion)")
        }
        XCTAssertLessThanOrEqual(result.exposedFiles.count, 2)
        XCTAssertEqual(result.indexedSensitivePaths.count, result.exposedFiles.count)
    }

    func testExposedAmongIndexedSkipsMissingPaths() throws {
        let root = try makeTemporaryDirectory()
        try writeFile("server.pem", in: root, contents: "dummy")

        let index = SensitivePathExposureIndex(sensitiveRelativePaths: ["server.pem", "removed.pem"])
        let exposed = checker.exposedAmongIndexed(
            index: index,
            sensitivePatterns: defaultSensitivePatterns,
            ignorePatternsByFile: [:],
            rootURL: root
        )

        XCTAssertEqual(exposed.map(\.relativePath), ["server.pem"])
    }

    func testUpdatedIndexTracksAddedAndRemovedSensitivePaths() throws {
        let root = try makeTemporaryDirectory()
        try writeFile("server.pem", in: root, contents: "dummy")

        let index = checker.updatedIndex(
            previousIndex: nil,
            changedRelativePaths: ["server.pem", "README.md"],
            sensitivePatterns: defaultSensitivePatterns,
            rootURL: root
        )
        XCTAssertEqual(index.sensitiveRelativePaths, ["server.pem"])

        try FileManager.default.removeItem(at: root.appendingPathComponent("server.pem"))
        let afterDelete = checker.updatedIndex(
            previousIndex: index,
            changedRelativePaths: ["server.pem"],
            sensitivePatterns: defaultSensitivePatterns,
            rootURL: root
        )
        XCTAssertTrue(afterDelete.sensitiveRelativePaths.isEmpty)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("SensitivePathExposureCheckerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        temporaryDirectories.append(url)
        return url
    }

    private func writeFile(_ relativePath: String, in rootURL: URL, contents: String) throws {
        let url = rootURL.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }
}
