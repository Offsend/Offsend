import XCTest
import DetectionCore
@testable import AIDetectionCore
import OnnxRuntimeBindings

final class ONNXRuntimeSessionBuilderTests: XCTestCase {
    func testCoreMLAvailabilityDoesNotCrash() {
        _ = ORTIsCoreMLExecutionProviderAvailable()
    }
}
