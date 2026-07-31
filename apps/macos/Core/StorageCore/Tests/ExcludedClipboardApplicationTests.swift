import StorageCore
import XCTest

final class ExcludedClipboardApplicationTests: XCTestCase {
    private let figma = ExcludedClipboardApplication(displayName: "Figma", bundleIdentifier: "com.figma.Desktop")
    private let excluded = [
        ExcludedClipboardApplication(displayName: "Figma", bundleIdentifier: "com.figma.Desktop")
    ]

    func testMatchesExactBundleIdentifier() {
        XCTAssertEqual(
            ExcludedClipboardApplication.matches(bundleIdentifier: "com.figma.Desktop", in: excluded),
            figma
        )
    }

    func testMatchesBundleIdentifierCaseInsensitively() {
        XCTAssertEqual(
            ExcludedClipboardApplication.matches(bundleIdentifier: "COM.FIGMA.DESKTOP", in: excluded),
            figma
        )
    }

    func testDoesNotMatchUnlistedBundleIdentifier() {
        XCTAssertNil(
            ExcludedClipboardApplication.matches(bundleIdentifier: "com.apple.Safari", in: excluded)
        )
    }

    func testDefaultSettingsIncludeFigma() {
        XCTAssertTrue(
            AppSettings.default.excludedClipboardApplications.contains {
                $0.bundleIdentifier.caseInsensitiveCompare("com.figma.Desktop") == .orderedSame
            }
        )
    }
}
