import XCTest
@testable import DetectionCore
import OnnxRuntimeBindings

final class ONNXRuntimeSessionBuilderTests: XCTestCase {
    func testCoreMLAvailabilityDoesNotCrash() {
        _ = ORTIsCoreMLExecutionProviderAvailable()
    }
}
