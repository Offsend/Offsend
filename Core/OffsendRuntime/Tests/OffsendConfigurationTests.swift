import DetectionCore
import StorageCore
import XCTest
@testable import OffsendRuntime

final class OffsendConfigurationTests: XCTestCase {
    private var context: OffsendRuntimeContext {
        OffsendRuntimeContext(settings: .default, customDictionaries: [])
    }

    /// `offsend check` scans trusted repository files, so inline `offsend:ignore` opt-outs are honored.
    func testDocumentProcessingOptionsHonorInlineIgnore() {
        let options = OffsendConfiguration.documentProcessingOptions(context: context)
        XCTAssertTrue(options.detection.honorInlineIgnore)
    }

    /// The plain detection options (shared by clipboard/in-app flows) must NOT honor inline ignore.
    func testDetectionOptionsDoNotHonorInlineIgnoreByDefault() {
        let options = OffsendConfiguration.detectionOptions(context: context, enableAIDetection: false)
        XCTAssertFalse(options.honorInlineIgnore)
    }
}
