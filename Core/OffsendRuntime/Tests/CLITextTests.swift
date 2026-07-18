import XCTest
@testable import OffsendRuntime

final class CLITextTests: XCTestCase {
    func testJoinSectionsSkipsEmpty() {
        let text = CLIText.joinSections([
            ["a"],
            [],
            ["b", "c"],
        ])
        XCTAssertEqual(text, "a\n\nb\nc")
    }

    func testMarkersStayPlainWithoutColor() {
        let ui = CLIText(useColor: false)
        XCTAssertEqual(ui.ok("done"), "✓ done")
        XCTAssertEqual(ui.next("offsend show"), "→ Next: offsend show")
        XCTAssertFalse(ui.ok("done").contains("\u{001B}["))
    }

    func testMarkersColorWhenEnabled() {
        let ui = CLIText(useColor: true)
        XCTAssertTrue(ui.ok("done").contains("\u{001B}[32m"))
        XCTAssertTrue(ui.warn("careful").contains("\u{001B}[33m"))
        XCTAssertTrue(ui.fail("bad").contains("\u{001B}[31m"))
    }

    func testDoctorCommandStripsComment() {
        let command = DoctorReport.command(from: "offsend protect   # hide paths")
        XCTAssertEqual(command, "offsend protect")
    }
}
