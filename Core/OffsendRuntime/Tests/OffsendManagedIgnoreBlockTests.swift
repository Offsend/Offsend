import XCTest
@testable import OffsendRuntime

final class OffsendManagedIgnoreBlockTests: XCTestCase {
    func testCreatesBlockWhenMissing() {
        let result = OffsendManagedIgnoreBlock.upsert(patterns: ["secrets/", "*.pem"], into: "# mine\n")
        XCTAssertEqual(result.result, .updated)
        XCTAssertTrue(result.contents.contains("# mine"))
        XCTAssertTrue(result.contents.contains(OffsendManagedIgnoreBlock.startMarker))
        XCTAssertTrue(result.contents.contains("secrets/"))
        XCTAssertTrue(result.contents.contains("*.pem"))
        XCTAssertTrue(result.contents.contains(OffsendManagedIgnoreBlock.endMarker))
    }

    func testReplacesExistingManagedBlock() {
        let existing = """
        # user
        local-only/

        # >>> offsend managed
        old/
        # <<< offsend managed

        trailing/
        """
        let result = OffsendManagedIgnoreBlock.upsert(patterns: ["new/"], into: existing)
        XCTAssertEqual(result.result, .updated)
        XCTAssertTrue(result.contents.contains("# user"))
        XCTAssertTrue(result.contents.contains("local-only/"))
        XCTAssertTrue(result.contents.contains("trailing/"))
        XCTAssertTrue(result.contents.contains("new/"))
        XCTAssertFalse(result.contents.contains("old/"))
    }

    func testUnchangedWhenIdentical() {
        let existing = """
        # >>> offsend managed
        secrets/
        # <<< offsend managed
        """
        let result = OffsendManagedIgnoreBlock.upsert(patterns: ["secrets/"], into: existing)
        XCTAssertEqual(result.result, .unchanged)
    }

    func testPreservesUserLinesOutsideBlock() {
        let existing = """
        # custom
        my-secret.env

        # >>> offsend managed
        a/
        # <<< offsend managed
        """
        let result = OffsendManagedIgnoreBlock.upsert(patterns: ["a/", "b/"], into: existing)
        XCTAssertTrue(result.contents.contains("my-secret.env"))
        XCTAssertTrue(result.contents.contains("b/"))
    }

    func testMalformedWhenOnlyStartMarker() {
        let existing = "# >>> offsend managed\nfoo/\n"
        let result = OffsendManagedIgnoreBlock.upsert(patterns: ["bar/"], into: existing)
        if case .malformed = result.result {
            // expected
        } else {
            XCTFail("Expected malformed, got \(result.result)")
        }
    }

    func testPatternsExtraction() {
        let contents = """
        x/
        # >>> offsend managed
        a/
        b/
        # <<< offsend managed
        y/
        """
        XCTAssertEqual(OffsendManagedIgnoreBlock.patterns(in: contents), ["a/", "b/"])
    }

    func testPatternsExtractionEmptyBlock() {
        let contents = """
        # >>> offsend managed
        # <<< offsend managed
        """
        XCTAssertEqual(OffsendManagedIgnoreBlock.patterns(in: contents), [])
    }

    func testNormalizeDropsDuplicatesCommentsAndBlanks() {
        let normalized = OffsendManagedIgnoreBlock.normalizePatterns(
            ["secrets/", "  secrets/  ", "# comment", "", "*.pem"]
        )
        XCTAssertEqual(normalized, ["secrets/", "*.pem"])
    }

    func testUpsertIntoFileWithoutTrailingNewline() {
        let result = OffsendManagedIgnoreBlock.upsert(patterns: ["a/"], into: "# mine")
        XCTAssertEqual(result.result, .updated)
        XCTAssertTrue(result.contents.hasPrefix("# mine"))
        XCTAssertTrue(result.contents.contains("a/"))
        XCTAssertTrue(result.contents.hasSuffix("\n"))
    }

    func testUpsertPreservesTextAfterBlockWithoutTrailingNewline() {
        let existing = "# >>> offsend managed\nold/\n# <<< offsend managed\ntail/"
        let result = OffsendManagedIgnoreBlock.upsert(patterns: ["new/"], into: existing)
        XCTAssertEqual(result.result, .updated)
        XCTAssertTrue(result.contents.contains("tail/"))
        XCTAssertFalse(result.contents.contains("old/"))
    }

    func testUpsertEmptyPatternsRendersEmptyBlock() {
        let result = OffsendManagedIgnoreBlock.upsert(patterns: [], into: nil)
        XCTAssertEqual(result.result, .created)
        XCTAssertEqual(
            result.contents,
            "\(OffsendManagedIgnoreBlock.startMarker)\n\(OffsendManagedIgnoreBlock.endMarker)\n"
        )
    }

    func testSectionedBlocksDoNotShadowEachOther() {
        let first = OffsendManagedIgnoreBlock.upsert(patterns: [".cursorignore"], into: nil, section: "ignore-files")
        let second = OffsendManagedIgnoreBlock.upsert(
            patterns: [".offsend/hooks/"],
            into: first.contents,
            section: "hooks"
        )
        XCTAssertEqual(second.result, .updated)
        XCTAssertTrue(second.contents.contains(".cursorignore"))
        XCTAssertTrue(second.contents.contains(".offsend/hooks/"))
        XCTAssertTrue(second.contents.contains("# >>> offsend managed: ignore-files"))
        XCTAssertTrue(second.contents.contains("# >>> offsend managed: hooks"))

        // Re-upserting one section must not disturb the other.
        let third = OffsendManagedIgnoreBlock.upsert(
            patterns: [".claudeignore"],
            into: second.contents,
            section: "ignore-files"
        )
        XCTAssertTrue(third.contents.contains(".claudeignore"))
        XCTAssertFalse(third.contents.contains(".cursorignore"))
        XCTAssertTrue(third.contents.contains(".offsend/hooks/"))

        XCTAssertEqual(
            OffsendManagedIgnoreBlock.patterns(in: third.contents, section: "hooks"),
            [".offsend/hooks/"]
        )
        XCTAssertEqual(
            OffsendManagedIgnoreBlock.patterns(in: third.contents, section: "ignore-files"),
            [".claudeignore"]
        )
        // No unsectioned block exists in this file.
        XCTAssertNil(OffsendManagedIgnoreBlock.patterns(in: third.contents))
    }

    func testUpsertDeduplicatesRepeatedBlocks() {
        let existing = """
        # >>> offsend managed
        a/
        # <<< offsend managed
        user/
        # >>> offsend managed
        b/
        # <<< offsend managed
        """
        let result = OffsendManagedIgnoreBlock.upsert(patterns: ["c/"], into: existing)
        XCTAssertEqual(result.result, .updated)
        XCTAssertTrue(result.contents.contains("c/"))
        XCTAssertTrue(result.contents.contains("user/"))
        XCTAssertFalse(result.contents.contains("a/"))
        XCTAssertFalse(result.contents.contains("b/"))
        let occurrences = result.contents.components(separatedBy: OffsendManagedIgnoreBlock.startMarker).count - 1
        XCTAssertEqual(occurrences, 1)
    }

    func testRemovingSection() {
        let contents = """
        # user line
        # >>> offsend managed: ignore-files
        .cursorignore
        # <<< offsend managed: ignore-files
        # >>> offsend managed: hooks
        .offsend/hooks/
        # <<< offsend managed: hooks
        """
        let cleaned = OffsendManagedIgnoreBlock.removing(section: "ignore-files", from: contents)
        XCTAssertNotNil(cleaned)
        XCTAssertFalse(cleaned!.contains(".cursorignore"))
        XCTAssertTrue(cleaned!.contains(".offsend/hooks/"))
        XCTAssertTrue(cleaned!.contains("# user line"))

        XCTAssertNil(OffsendManagedIgnoreBlock.removing(section: "missing", from: contents))
    }

    func testMarkerInsideLineIsNotTreatedAsBlock() {
        // Markers must occupy a whole line; a mention inside a comment is user text.
        let existing = "# see docs about '# >>> offsend managed' markers and # <<< offsend managed too\n"
        let result = OffsendManagedIgnoreBlock.upsert(patterns: ["a/"], into: existing)
        XCTAssertEqual(result.result, .updated)
        XCTAssertTrue(result.contents.contains("see docs"))
        XCTAssertTrue(result.contents.contains("a/"))
    }
}
