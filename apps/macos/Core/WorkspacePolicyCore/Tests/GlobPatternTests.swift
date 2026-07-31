import XCTest
@testable import WorkspacePolicyCore

final class GlobPatternTests: XCTestCase {
    func testSingleStarMatchesWithinSegment() {
        let glob = GlobPattern("*.pem")

        XCTAssertTrue(glob.matches("id.pem"))
        XCTAssertFalse(glob.matches("nested/id.pem"))
    }

    func testDoubleStarMatchesAcrossSegments() {
        let glob = GlobPattern("**/*.pem")

        XCTAssertTrue(glob.matches("nested/id.pem"))
        XCTAssertTrue(glob.matches("deep/nested/id.pem"))
    }

    func testLeadingDoubleStarMatchesZeroSegments() {
        let glob = GlobPattern("**/*.mdc")

        XCTAssertTrue(glob.matches("notes.mdc"), "`**/` must also match a root-level file (zero leading segments).")
        XCTAssertTrue(glob.matches("vendor/notes.mdc"))
    }

    func testMiddleDoubleStarMatchesZeroSegments() {
        let glob = GlobPattern("a/**/b")

        XCTAssertTrue(glob.matches("a/b"), "`a/**/b` must match with zero intermediate segments.")
        XCTAssertTrue(glob.matches("a/x/b"))
        XCTAssertTrue(glob.matches("a/x/y/b"))
        XCTAssertFalse(glob.matches("a/b/c"))
    }

    func testQuestionMarkMatchesSingleCharacter() {
        let glob = GlobPattern(".env?")

        XCTAssertTrue(glob.matches(".env."))
        XCTAssertFalse(glob.matches(".env.local"))
    }

    func testDirectoryGlob() {
        let glob = GlobPattern(".cursor/rules/*.mdc")

        XCTAssertTrue(glob.matches(".cursor/rules/privacy.mdc"))
        XCTAssertFalse(glob.matches(".cursor/rules/nested/privacy.mdc"))
    }

    func testTrailingSlashDirDoesNotMatchDescendants() {
        // Document GlobPattern semantics: trailing `/` is literal, unlike gitignore dirs.
        let glob = GlobPattern(".kube/")
        XCTAssertTrue(glob.matches(".kube/"))
        XCTAssertFalse(glob.matches(".kube/config"))
    }

    func testDoubleStarDirMatchesDescendants() {
        let glob = GlobPattern(".kube/**")
        XCTAssertTrue(glob.matches(".kube/config"))
        XCTAssertTrue(glob.matches(".kube/cache/http"))
        XCTAssertFalse(glob.matches("kube/config"))
    }
}
