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
}
