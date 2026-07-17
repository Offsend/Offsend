import XCTest
@testable import OffsendRuntime

final class ProjectConfigIgnoreMutatorTests: XCTestCase {
    func testAppendsIgnoreSectionBeforeHooks() throws {
        let yaml = """
        version: 1

        check:
          fail_on: block

        hooks:
          type: pre-commit
        """
        let merged = try ProjectConfigIgnoreMutator.mergingPatterns(intoYAML: yaml, patterns: ["secrets/"])
        XCTAssertEqual(merged.added, ["secrets/"])
        XCTAssertTrue(merged.yaml.contains("ignore:"))
        XCTAssertTrue(merged.yaml.contains("patterns:"))
        XCTAssertTrue(merged.yaml.contains("secrets/"))
        // ignore should appear before hooks
        let ignoreIdx = merged.yaml.range(of: "ignore:")!.lowerBound
        let hooksIdx = merged.yaml.range(of: "hooks:")!.lowerBound
        XCTAssertLessThan(ignoreIdx, hooksIdx)
    }

    func testMergesIntoExistingPatterns() throws {
        let yaml = """
        version: 1
        ignore:
          commit: false
          patterns:
            - "a/"
        hooks:
          type: pre-commit
        """
        let merged = try ProjectConfigIgnoreMutator.mergingPatterns(intoYAML: yaml, patterns: ["a/", "b/"])
        XCTAssertEqual(merged.added, ["b/"])
        XCTAssertTrue(merged.yaml.contains("a/"))
        XCTAssertTrue(merged.yaml.contains("b/"))
        XCTAssertTrue(merged.yaml.contains("commit: false"))
    }

    func testMergesIntoFlowStylePatternsWithoutLosingEntries() throws {
        let yaml = """
        version: 1
        ignore:
          commit: false
          patterns: ["secrets/", '*.pem']
        hooks:
          type: pre-commit
        """
        let merged = try ProjectConfigIgnoreMutator.mergingPatterns(intoYAML: yaml, patterns: ["b/"])
        XCTAssertEqual(merged.added, ["b/"])
        XCTAssertTrue(merged.yaml.contains("secrets/"), "flow-style entries must survive the merge")
        XCTAssertTrue(merged.yaml.contains("*.pem"))
        XCTAssertTrue(merged.yaml.contains("b/"))
        XCTAssertTrue(merged.yaml.contains("commit: false"))
    }

    func testFlowStyleListWithTrailingCommentIsParsed() throws {
        let yaml = """
        version: 1
        ignore:
          patterns: ["a/"] # keep
        """
        let merged = try ProjectConfigIgnoreMutator.mergingPatterns(intoYAML: yaml, patterns: ["b/"])
        XCTAssertEqual(merged.added, ["b/"])
        XCTAssertTrue(merged.yaml.contains("a/"))
        XCTAssertTrue(merged.yaml.contains("b/"))
    }

    func testUnsupportedPatternsScalarThrowsInsteadOfDestroying() {
        let yaml = """
        version: 1
        ignore:
          patterns: not-a-list
        """
        XCTAssertThrowsError(
            try ProjectConfigIgnoreMutator.mergingPatterns(intoYAML: yaml, patterns: ["b/"])
        ) { error in
            guard case ProjectConfigIgnoreMutatorError.unsupportedPatternsValue = error else {
                return XCTFail("Expected unsupportedPatternsValue, got \(error)")
            }
        }
    }

    func testNestedIgnoreKeyIsNotMistakenForSection() throws {
        let yaml = """
        version: 1
        check:
          exclude:
            - "vendor/**"
          # a nested mapping that happens to contain an ignore key
          detectors:
            ignore: nothing
        """
        let merged = try ProjectConfigIgnoreMutator.mergingPatterns(intoYAML: yaml, patterns: ["secrets/"])
        XCTAssertEqual(merged.added, ["secrets/"])
        // A new top-level ignore section is appended; the nested key is untouched.
        XCTAssertTrue(merged.yaml.contains("ignore:\n  commit: false"))
        XCTAssertTrue(merged.yaml.contains("ignore: nothing"))
    }

    func testRoundTripDecode() throws {
        let yaml = """
        version: 1
        ignore:
          commit: false
          patterns:
            - "secrets/"
        hooks:
          type: pre-commit
          publish: false
        """
        let config = try ProjectConfigLoader().load(from: writeTemp(yaml))
        XCTAssertEqual(config?.ignore?.commit, false)
        XCTAssertEqual(config?.ignore?.patterns, ["secrets/"])
        XCTAssertEqual(config?.hooks?.publish, false)
        XCTAssertEqual(config?.hooks?.publishesHooks, false)
        XCTAssertEqual(config?.ignore?.commitsIgnoreFiles, false)
    }

    private func writeTemp(_ yaml: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try yaml.write(
            to: root.appendingPathComponent(ProjectConfigLoader.filename),
            atomically: true,
            encoding: .utf8
        )
        // Keep directory for loader; tests process cleanup is best-effort.
        return root
    }
}
