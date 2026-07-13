import XCTest
@testable import OffsendRuntime

final class PathExcludeMatcherCornerCaseTests: XCTestCase {
    func testEmptyPathIsNotExcluded() {
        XCTAssertFalse(PathExcludeMatcher.isExcluded(relativePath: "", patterns: ["**/*"]))
        XCTAssertFalse(PathExcludeMatcher.isExcluded(relativePath: "", patterns: ["vendor/**"]))
        XCTAssertFalse(PathExcludeMatcher.shouldSkipDirectory(relativePath: "", patterns: ["vendor/**"]))
    }

    func testNormalizesDotSlashBackslashAndLeadingSlash() {
        let patterns = ["vendor/**"]
        XCTAssertTrue(PathExcludeMatcher.isExcluded(relativePath: "./vendor/pkg/main.go", patterns: patterns))
        XCTAssertTrue(PathExcludeMatcher.isExcluded(relativePath: "vendor\\pkg\\main.go", patterns: patterns))
        XCTAssertTrue(PathExcludeMatcher.isExcluded(relativePath: "/vendor/pkg/main.go", patterns: patterns))
        XCTAssertTrue(PathExcludeMatcher.isExcluded(relativePath: "././vendor/x", patterns: patterns))
    }

    func testEmptyPatternsExcludeNothingButStillSkipGit() {
        XCTAssertFalse(PathExcludeMatcher.isExcluded(relativePath: "src/main.swift", patterns: []))
        XCTAssertTrue(PathExcludeMatcher.shouldSkipDirectory(relativePath: ".git", patterns: []))
        XCTAssertTrue(PathExcludeMatcher.shouldSkipDirectory(relativePath: "nested/.git", patterns: []))
    }

    func testBasenameGlobsMatchAtAnyDepth() {
        XCTAssertTrue(PathExcludeMatcher.isExcluded(relativePath: "Package.lock", patterns: ["*.lock"]))
        XCTAssertTrue(PathExcludeMatcher.isExcluded(relativePath: "apps/api/Cargo.lock", patterns: ["*.lock"]))
        XCTAssertTrue(PathExcludeMatcher.isExcluded(relativePath: "android/app/build/outputs/app-release.apk", patterns: ["*.apk"]))
        XCTAssertTrue(PathExcludeMatcher.isExcluded(relativePath: "User.xcuserstate", patterns: ["*.xcuserstate"]))
        XCTAssertFalse(PathExcludeMatcher.isExcluded(relativePath: "lockstep/readme.md", patterns: ["*.lock"]))
    }

    func testSimpleDirectoryPrefixDoesNotMatchPartialName() {
        // `build/**` must not exclude `buildtools/…`
        XCTAssertFalse(PathExcludeMatcher.isExcluded(relativePath: "buildtools/clang", patterns: ["build/**"]))
        XCTAssertTrue(PathExcludeMatcher.isExcluded(relativePath: "build/output.bin", patterns: ["build/**"]))
        XCTAssertTrue(PathExcludeMatcher.isExcluded(relativePath: "build", patterns: ["build/**"]))
    }

    func testNestedDirectoryGlobDoesNotMatchPartialSegment() {
        XCTAssertFalse(PathExcludeMatcher.isExcluded(
            relativePath: "packages/node_modules_backup/index.js",
            patterns: ["**/node_modules/**"]
        ))
        XCTAssertFalse(PathExcludeMatcher.isExcluded(
            relativePath: "apps/mybuild/main.swift",
            patterns: ["**/build/**"]
        ))
        XCTAssertFalse(PathExcludeMatcher.isExcluded(
            relativePath: "building/docs.md",
            patterns: ["**/build/**"]
        ))
        XCTAssertTrue(PathExcludeMatcher.isExcluded(
            relativePath: "apps/build/main.swift",
            patterns: ["**/build/**"]
        ))
    }

    func testMultiSegmentNestedGlobs() {
        XCTAssertTrue(PathExcludeMatcher.isExcluded(
            relativePath: "Tuist/.build/checkouts/A/Package.swift",
            patterns: ["**/Tuist/.build/**"]
        ))
        XCTAssertTrue(PathExcludeMatcher.isExcluded(
            relativePath: "Apps/Demo/Tuist/Dependencies/SwiftPackageManager/.build/foo",
            patterns: ["**/Tuist/Dependencies/**"]
        ))
        XCTAssertTrue(PathExcludeMatcher.isExcluded(
            relativePath: "vendor/bundle/ruby/3.2.0/gems/x/lib/x.rb",
            patterns: ["**/vendor/bundle/**"]
        ))
        XCTAssertTrue(PathExcludeMatcher.isExcluded(
            relativePath: "ios/Carthage/Build/iOS/Foo.framework/Foo",
            patterns: ["**/Carthage/Build/**"]
        ))
        // Go vendor is broader than Ruby's vendor/bundle
        XCTAssertTrue(PathExcludeMatcher.isExcluded(
            relativePath: "vendor/github.com/foo/bar.go",
            patterns: ["**/vendor/**"]
        ))
        XCTAssertFalse(PathExcludeMatcher.isExcluded(
            relativePath: "Sources/VendorHelper.swift",
            patterns: ["**/vendor/**"]
        ))
    }

    func testEggInfoAndXcarchiveWildcardDirectories() {
        XCTAssertTrue(PathExcludeMatcher.isExcluded(
            relativePath: "my_pkg.egg-info/SOURCES.txt",
            patterns: ["*.egg-info/**"]
        ))
        XCTAssertTrue(PathExcludeMatcher.isExcluded(
            relativePath: "dist/my_pkg.egg-info/PKG-INFO",
            patterns: ["**/*.egg-info/**"]
        ))
        XCTAssertTrue(PathExcludeMatcher.isExcluded(
            relativePath: "App.xcarchive/Info.plist",
            patterns: ["*.xcarchive/**"]
        ))
        XCTAssertFalse(PathExcludeMatcher.isExcluded(
            relativePath: "App.xcarchiveinfo/readme",
            patterns: ["*.xcarchive/**"]
        ))
    }

    func testShouldSkipDirectoryMatchesDirectoryRootItself() {
        XCTAssertTrue(PathExcludeMatcher.shouldSkipDirectory(
            relativePath: "node_modules",
            patterns: ["**/node_modules/**"]
        ))
        XCTAssertTrue(PathExcludeMatcher.shouldSkipDirectory(
            relativePath: "vendor",
            patterns: ["vendor/**"]
        ))
        XCTAssertTrue(PathExcludeMatcher.shouldSkipDirectory(
            relativePath: "app/build",
            patterns: ["**/build/**"]
        ))
        XCTAssertFalse(PathExcludeMatcher.shouldSkipDirectory(
            relativePath: "app",
            patterns: ["**/build/**"]
        ))
    }

    func testFilterDropsExcludedFilesAndKeepsOthers() {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("offsend-exclude-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let kept = root.appendingPathComponent("src/main.swift")
        let dropped = root.appendingPathComponent("node_modules/pkg/index.js")
        let lock = root.appendingPathComponent("apps/Cargo.lock")

        let filtered = PathExcludeMatcher.filter(
            fileURLs: [kept, dropped, lock],
            excludePatterns: ["**/node_modules/**", "*.lock"],
            workingDirectory: root
        )

        XCTAssertEqual(filtered.map(\.path), [kept.path])
    }

    func testFilterWithEmptyPatternsReturnsInput() {
        let url = URL(fileURLWithPath: "/tmp/a.swift")
        let filtered = PathExcludeMatcher.filter(
            fileURLs: [url],
            excludePatterns: [],
            workingDirectory: URL(fileURLWithPath: "/tmp")
        )
        XCTAssertEqual(filtered, [url])
    }

    func testRelativePathOutsideWorkingDirectoryFallsBackToBasename() {
        let working = URL(fileURLWithPath: "/tmp/project-a")
        let outside = URL(fileURLWithPath: "/tmp/project-b/secret.lock")
        let relative = PathExcludeMatcher.relativePath(of: outside, relativeTo: working)
        XCTAssertEqual(relative, "secret.lock")
        XCTAssertTrue(PathExcludeMatcher.isExcluded(relativePath: relative, patterns: ["*.lock"]))
    }

    func testPathWithSlashPatternUsesFnmatch() {
        XCTAssertTrue(PathExcludeMatcher.isExcluded(
            relativePath: "config/production.env",
            patterns: ["config/*.env"]
        ))
        XCTAssertFalse(PathExcludeMatcher.isExcluded(
            relativePath: "config/nested/production.env",
            patterns: ["config/*.env"]
        ))
    }
}

final class ProjectConfigTemplateCornerCaseTests: XCTestCase {
    func testResolveIgnoresEmptyAndWhitespaceCSVParts() throws {
        let ids = try ProjectConfigTemplates.resolve(rawValues: ["", "  ", ",,", " , node , , swift "])
        XCTAssertEqual(ids, [.common, .node, .swift])
    }

    func testResolveExplicitCommonDoesNotDuplicate() throws {
        let ids = try ProjectConfigTemplates.resolve(rawValues: ["common", "COMMON", "node"])
        XCTAssertEqual(ids, [.common, .node])
    }

    func testResolveAliasAndCanonicalDedupes() throws {
        let ids = try ProjectConfigTemplates.resolve(rawValues: ["js", "node", "ts", "javascript", "ios", "swift"])
        XCTAssertEqual(ids, [.common, .node, .swift])
    }

    func testResolveUnknownPreservesOriginalTokenInError() {
        XCTAssertThrowsError(try ProjectConfigTemplates.resolve(rawValues: ["NodeJS"])) { error in
            guard case ProjectConfigTemplateError.unknownTemplate(let token) = error else {
                return XCTFail("Expected unknownTemplate, got \(error)")
            }
            XCTAssertEqual(token, "NodeJS")
            XCTAssertTrue(error.localizedDescription.contains("NodeJS"))
            XCTAssertTrue(error.localizedDescription.contains("node"))
        }
    }

    func testExcludePatternsInsertsCommonWhenMissing() {
        let patterns = ProjectConfigTemplates.excludePatterns(for: [.node])
        XCTAssertEqual(patterns.first, ProjectConfigTemplateID.common.excludePatterns.first)
        XCTAssertTrue(patterns.contains("**/node_modules/**"))
    }

    func testExcludePatternsAllTemplatesHaveNoDuplicates() {
        let patterns = ProjectConfigTemplates.excludePatterns(for: ProjectConfigTemplateID.allCases)
        XCTAssertEqual(patterns.count, Set(patterns).count)
        XCTAssertFalse(patterns.isEmpty)
    }

    func testEveryTemplatePatternMatchesARepresentativePath() throws {
        let samples: [ProjectConfigTemplateID: [String]] = [
            .common: [
                "Cargo.lock",
                "apps/web/dist/index.js",
                "module/build/out.bin",
                ".DS_Store",
                "bundle.min.js",
                "app.js.map",
                ".eslintcache",
            ],
            .node: [
                "packages/ui/node_modules/x/index.js",
                "apps/web/.next/cache",
                "file.tsbuildinfo",
                "package-lock.json",
                "apps/web/pnpm-lock.yaml",
                "npm-shrinkwrap.json",
                ".parcel-cache/x",
                "storybook-static/index.html",
            ],
            .python: [
                ".venv/bin/python",
                "src/__pycache__/a.pyc",
                "pkg.egg-info/PKG-INFO",
                ".ipynb_checkpoints/notebook.ipynb",
                "module.pyc",
            ],
            .go: ["vendor/github.com/foo/bar.go", "go.sum"],
            .rust: ["target/release/app"],
            .ruby: ["vendor/bundle/ruby/3.2.0/gems/x.rb", ".bundle/config"],
            .java: [".gradle/caches/x", "out/production/main", "target/classes/A.class", "App.class", "lib.jar"],
            .android: ["app/.cxx/Debug/x", "app-release.apk", "classes.dex", "Foo.class"],
            .swift: [
                "DerivedData/ModuleCache",
                ".build/debug/App",
                "Pods/Alamofire/x.swift",
                "Package.resolved",
                "App.ipa",
                "App.app.dSYM/Contents/Resources/DWARF/App",
            ],
            .tuist: ["Derived/Sources/TuistBundle+X.swift", "Tuist/.build/checkouts/A"],
        ]

        for id in ProjectConfigTemplateID.allCases {
            let patterns = id.excludePatterns
            let paths = try XCTUnwrap(samples[id], "Missing samples for \(id.rawValue)")
            for path in paths {
                XCTAssertTrue(
                    PathExcludeMatcher.isExcluded(relativePath: path, patterns: patterns),
                    "\(id.rawValue) patterns should exclude \(path)"
                )
            }
        }
    }

    func testMergeExcludeListsPreservesOrderAndReportsAdded() {
        let result = ProjectConfigTemplates.mergeExcludeLists(
            existing: ["*.lock", "custom/**"],
            additional: ["**/dist/**", "*.lock", "**/node_modules/**"]
        )
        XCTAssertEqual(result.merged, ["*.lock", "custom/**", "**/dist/**", "**/node_modules/**"])
        XCTAssertEqual(result.added, ["**/dist/**", "**/node_modules/**"])
    }

    func testMergeExcludeListsWhenNothingNew() {
        let result = ProjectConfigTemplates.mergeExcludeLists(
            existing: ["*.lock"],
            additional: ["*.lock"]
        )
        XCTAssertEqual(result.merged, ["*.lock"])
        XCTAssertTrue(result.added.isEmpty)
    }

    func testMergingExcludeEmptyInlineArray() throws {
        let existing = """
        version: 1
        check:
          fail_on: block
          exclude: []
          policy: false
        """
        let result = try ProjectConfigTemplates.mergingExclude(
            intoYAML: existing,
            patterns: ["**/node_modules/**"]
        )
        XCTAssertEqual(result.added, ["**/node_modules/**"])
        XCTAssertTrue(result.yaml.contains("**/node_modules/**"))
        XCTAssertTrue(result.yaml.contains("policy: false"))
        XCTAssertFalse(result.yaml.contains("exclude: []"))
    }

    func testMergingExcludeWhenKeyMissingInsertsUnderCheck() throws {
        let existing = """
        version: 1
        check:
          fail_on: block
          policy: false
        hooks:
          type: pre-commit
        """
        let result = try ProjectConfigTemplates.mergingExclude(
            intoYAML: existing,
            patterns: ["*.lock"]
        )
        XCTAssertEqual(result.added, ["*.lock"])
        XCTAssertTrue(result.yaml.contains("exclude:"))
        XCTAssertTrue(result.yaml.contains("*.lock"))
        XCTAssertTrue(result.yaml.contains("hooks:"))
    }

    func testMergingExcludeWhenCheckMissingAppendsCheckBlock() throws {
        let existing = """
        version: 1
        """
        let result = try ProjectConfigTemplates.mergingExclude(
            intoYAML: existing,
            patterns: ["**/build/**"]
        )
        XCTAssertTrue(result.yaml.contains("check:"))
        XCTAssertTrue(result.yaml.contains("**/build/**"))
    }

    func testMergingExcludeParsesSingleQuotedAndUnquotedItems() throws {
        let existing = """
        version: 1
        check:
          exclude:
            - 'custom/**'
            - already/**
          detectors:
            disable:
              - email
        """
        let result = try ProjectConfigTemplates.mergingExclude(
            intoYAML: existing,
            patterns: ["custom/**", "**/node_modules/**"]
        )
        XCTAssertEqual(result.added, ["**/node_modules/**"])
        XCTAssertTrue(result.yaml.contains("custom/**"))
        XCTAssertTrue(result.yaml.contains("already/**"))
        XCTAssertTrue(result.yaml.contains("- email"))
    }

    func testMergingExcludeSkipsCommentsBetweenItems() throws {
        let existing = """
        version: 1
        check:
          exclude:
            - "*.lock"
            # keep secrets scannable
            - "vendor/**"
          dictionaries: []
        """
        let result = try ProjectConfigTemplates.mergingExclude(
            intoYAML: existing,
            patterns: ["**/dist/**"]
        )
        XCTAssertEqual(Set(result.added), ["**/dist/**"])
        XCTAssertTrue(result.yaml.contains("*.lock"))
        XCTAssertTrue(result.yaml.contains("vendor/**"))
        XCTAssertTrue(result.yaml.contains("dictionaries: []"))
    }

    func testRenderYAMLCommonOnlyHasNoTemplateFlagInGeneratedBy() {
        let yaml = ProjectConfigTemplates.renderYAML(templates: [.common])
        XCTAssertTrue(yaml.contains("# Generated by: offsend init\n"))
        XCTAssertFalse(yaml.contains("--template"))
        XCTAssertTrue(yaml.contains("# templates: common"))
        XCTAssertTrue(yaml.contains("# - \"**/tmp/**\""))
        XCTAssertTrue(yaml.contains("# - \"**/temp/**\""))
        XCTAssertTrue(yaml.contains("# - \"**/.cache/**\""))
        XCTAssertFalse(yaml.contains("\n    - \"**/tmp/**\""))
        XCTAssertFalse(yaml.contains("\n    - \"**/temp/**\""))
        XCTAssertFalse(yaml.contains("\n    - \"**/.cache/**\""))
    }

    func testCommonActivePatternsDoNotExcludeTmpOrCache() {
        let patterns = ProjectConfigTemplates.excludePatterns(for: [.common])
        XCTAssertFalse(patterns.contains("**/tmp/**"))
        XCTAssertFalse(patterns.contains("**/temp/**"))
        XCTAssertFalse(patterns.contains("**/.cache/**"))
        XCTAssertFalse(PathExcludeMatcher.isExcluded(relativePath: "tmp/credentials.env", patterns: patterns))
        XCTAssertFalse(PathExcludeMatcher.isExcluded(relativePath: ".cache/token", patterns: patterns))
    }

    func testRenderYAMLWithoutCommonStillIncludesCommon() throws {
        let yaml = ProjectConfigTemplates.renderYAML(templates: [.android])
        XCTAssertTrue(yaml.contains("# templates: common, android"))

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent(".git"), withIntermediateDirectories: true)
        try yaml.write(to: root.appendingPathComponent(".offsend.yml"), atomically: true, encoding: .utf8)

        let config = try XCTUnwrap(ProjectConfigLoader().load(from: root))
        let exclude = try XCTUnwrap(config.check?.exclude)
        XCTAssertTrue(exclude.contains("**/build/**"))
        XCTAssertTrue(exclude.contains("*.apk"))
    }

    func testRenderedPatternsRoundTripThroughMatcher() {
        let patterns = ProjectConfigTemplates.excludePatterns(for: [.node, .python, .swift])
        let mustExclude = [
            "apps/web/node_modules/x/index.js",
            "src/__pycache__/a.pyc",
            "DerivedData/Foo",
            "poetry.lock",
        ]
        for path in mustExclude {
            XCTAssertTrue(
                PathExcludeMatcher.isExcluded(relativePath: path, patterns: patterns),
                "Expected exclude for \(path)"
            )
        }
        XCTAssertFalse(PathExcludeMatcher.isExcluded(relativePath: "Sources/App.swift", patterns: patterns))
        XCTAssertFalse(PathExcludeMatcher.isExcluded(relativePath: ".env", patterns: patterns))
    }
}
