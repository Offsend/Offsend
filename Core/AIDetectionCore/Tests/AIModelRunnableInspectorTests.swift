import XCTest
import DetectionCore
@testable import AIDetectionCore

final class AIModelRunnableInspectorTests: XCTestCase {
    func testRemotePathsWithONNXAreRunnable() {
        let inspection = AIModelRunnableInspector.inspectRemoteFilePaths([
            "config.json",
            "onnx/model.onnx",
            "tokenizer.json",
        ])
        XCTAssertTrue(inspection.isRunnable)
        XCTAssertEqual(inspection.format, .onnxTokenClassification)
    }

    func testRemotePathsWithSafetensorsOnlyAreRejected() {
        let inspection = AIModelRunnableInspector.inspectRemoteFilePaths([
            "config.json",
            "model.safetensors",
            "tokenizer.json",
        ])
        XCTAssertFalse(inspection.isRunnable)
        XCTAssertNotNil(inspection.reason)
    }

    func testRemoteONNXWithoutTokenizerIsRejected() {
        let inspection = AIModelRunnableInspector.inspectRemoteFilePaths([
            "config.json",
            "onnx/model.onnx",
        ])
        XCTAssertFalse(inspection.isRunnable)
        XCTAssertNotNil(inspection.reason)
    }

    func testLocalONNXWithoutTokenizerIsRejected() {
        let validation = AIModelBundleValidation(
            format: .onnxTokenClassification,
            onnxModelPath: "model.onnx"
        )
        XCTAssertFalse(validation.runnableInspection.isRunnable)
    }

    func testRemotePathsWithGGUFAreRunnable() {
        let inspection = AIModelRunnableInspector.inspectRemoteFilePaths(["model.gguf"])
        XCTAssertTrue(inspection.isRunnable)
        XCTAssertEqual(inspection.format, .gguf)
    }

    func testLocalSafetensorsValidationIsNotRunnable() {
        let validation = AIModelBundleValidation(format: .huggingFaceTransformers)
        XCTAssertFalse(validation.runnableInspection.isRunnable)
    }

    func testLocalONNXValidationIsRunnable() throws {
        let validation = AIModelBundleValidation(
            format: .onnxTokenClassification,
            onnxModelPath: "model.onnx",
            tokenizerPath: "tokenizer.json"
        )
        XCTAssertTrue(validation.runnableInspection.isRunnable)
    }

    func testGGUFValidationIsRunnableWithPath() {
        let validation = AIModelBundleValidation(format: .gguf, ggufModelPath: "model.gguf")
        XCTAssertTrue(validation.runnableInspection.isRunnable)
    }

    func testOllamaAPIValidationIsRunnable() {
        let validation = AIModelBundleValidation(format: .ollamaAPI)
        XCTAssertTrue(validation.runnableInspection.isRunnable)
    }
}
