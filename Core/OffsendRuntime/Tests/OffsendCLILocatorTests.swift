import XCTest
@testable import OffsendRuntime

final class OffsendCLILocatorTests: XCTestCase {
    func testAppBundleMainExecutablePathsAreNotTreatedAsCLI() {
        XCTAssertTrue(
            OffsendCLILocator.isAppBundleMainExecutablePath("/Applications/Offsend.app/Contents/MacOS/Offsend")
        )
        XCTAssertTrue(
            OffsendCLILocator.isAppBundleMainExecutablePath("/Applications/Offsend.app/Contents/MacOS/offsend")
        )
        XCTAssertFalse(
            OffsendCLILocator.isAppBundleMainExecutablePath("/Applications/Offsend.app/Contents/Helpers/offsend")
        )
        XCTAssertFalse(
            OffsendCLILocator.isAppBundleMainExecutablePath("/opt/homebrew/bin/offsend")
        )
    }
}
