import XCTest
@testable import DetectionCore

final class HuggingFaceModelDownloaderTests: XCTestCase {
    func testRetainsOnlyPreferredONNXVariant() {
        let paths = [
            "config.json",
            "tokenizer.json",
            "onnx/model.onnx",
            "onnx/model_fp16.onnx",
            "onnx/model_int8.onnx",
            "onnx/model_quantized.onnx",
        ]

        let retained = HuggingFaceModelDownloader.retainedPaths(forAvailable: paths)

        XCTAssertEqual(
            retained,
            ["config.json", "tokenizer.json", "onnx/model_int8.onnx"],
            "Only the variant that the runtime will load should be downloaded"
        )
    }

    func testKeepsExternalWeightsOnlyForPreferredVariant() {
        let paths = [
            "config.json",
            "tokenizer.json",
            "onnx/model.onnx",
            "onnx/model.onnx.data",
            "onnx/model_int8.onnx",
            "onnx/model_int8.onnx_data",
        ]

        let retained = HuggingFaceModelDownloader.retainedPaths(forAvailable: paths)

        XCTAssertTrue(retained.contains("onnx/model_int8.onnx"))
        XCTAssertTrue(retained.contains("onnx/model_int8.onnx_data"))
        XCTAssertFalse(retained.contains("onnx/model.onnx"), "fp32 variant must be skipped")
        XCTAssertFalse(retained.contains("onnx/model.onnx.data"), "fp32 external weights must be skipped")
    }

    func testKeepsEverythingWhenRepoHasNoONNXFiles() {
        let paths = ["config.json", "tokenizer.json", "model.gguf"]
        XCTAssertEqual(HuggingFaceModelDownloader.retainedPaths(forAvailable: paths), Set(paths))
    }
}
