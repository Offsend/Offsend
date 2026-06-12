import XCTest
import DetectionCore
@testable import AIDetectionCore

final class AIModelBundleValidatorTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDirectory)
    }

    func testDetectsCoreMLPackage() throws {
        let package = tempDirectory.appendingPathComponent("model.mlpackage", isDirectory: true)
        try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: tempDirectory.appendingPathComponent("config.json"))
        try Data("{}".utf8).write(to: tempDirectory.appendingPathComponent("tokenizer.json"))

        let validation = try AIModelBundleValidator.validate(directory: tempDirectory)
        XCTAssertEqual(validation.format, .coreML)
        XCTAssertEqual(validation.coreMLModelPath, "model.mlpackage")
    }

    func testDetectsONNXBundle() throws {
        try Data().write(to: tempDirectory.appendingPathComponent("model.onnx"))
        try Data("{}".utf8).write(to: tempDirectory.appendingPathComponent("tokenizer.json"))

        let validation = try AIModelBundleValidator.validate(directory: tempDirectory)
        XCTAssertEqual(validation.format, .onnxTokenClassification)
        XCTAssertEqual(validation.onnxModelPath, "model.onnx")
        XCTAssertEqual(validation.tokenizerPath, "tokenizer.json")
    }

    func testPrefersTokenizerJSONOverConfig() throws {
        try Data().write(to: tempDirectory.appendingPathComponent("model.onnx"))
        try Data("{}".utf8).write(to: tempDirectory.appendingPathComponent("tokenizer_config.json"))
        try Data("{}".utf8).write(to: tempDirectory.appendingPathComponent("tokenizer.json"))

        let validation = try AIModelBundleValidator.validate(directory: tempDirectory)
        XCTAssertEqual(validation.tokenizerPath, "tokenizer.json")
    }

    func testDetectsSafetensorsAsHuggingFaceTransformers() throws {
        try Data("{}".utf8).write(to: tempDirectory.appendingPathComponent("config.json"))
        try Data().write(to: tempDirectory.appendingPathComponent("model.safetensors"))

        let validation = try AIModelBundleValidator.validate(directory: tempDirectory)
        XCTAssertEqual(validation.format, .huggingFaceTransformers)
        XCTAssertFalse(validation.runnableInspection.isRunnable)
    }

    func testRejectsEmptyDirectory() {
        XCTAssertThrowsError(try AIModelBundleValidator.validate(directory: tempDirectory))
    }

    func testPrefersQuantizedONNXVariantDeterministically() throws {
        try Data().write(to: tempDirectory.appendingPathComponent("model.onnx"))
        try Data().write(to: tempDirectory.appendingPathComponent("model_fp16.onnx"))
        try Data().write(to: tempDirectory.appendingPathComponent("model_int8.onnx"))
        try Data("{}".utf8).write(to: tempDirectory.appendingPathComponent("tokenizer.json"))

        let validation = try AIModelBundleValidator.validate(directory: tempDirectory)
        XCTAssertEqual(validation.format, .onnxTokenClassification)
        XCTAssertEqual(validation.onnxModelPath, "model_int8.onnx")
    }
}
