import XCTest
import DetectionCore
@testable import AIDetectionCore

final class ManifestModelImporterTests: XCTestCase {
    private var tempRoot: URL!

    override func setUpWithError() throws {
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempRoot)
    }

    func testImportRejectsPathTraversalBeforeWriting() async throws {
        let payload = tempRoot.appendingPathComponent("payload.txt")
        try Data("pwned".utf8).write(to: payload)

        let escapeTarget = tempRoot.appendingPathComponent("escape.txt")
        XCTAssertFalse(FileManager.default.fileExists(atPath: escapeTarget.path))

        let modelDirectory = tempRoot.appendingPathComponent("Models/poc", isDirectory: true)
        try FileManager.default.createDirectory(at: modelDirectory, withIntermediateDirectories: true)

        // One `..` escapes `poc/` into `Models/`; two reach `tempRoot/escape.txt`.
        let manifestURL = tempRoot.appendingPathComponent("manifest.json")
        let manifestJSON = """
        {
          "id": "traversal-poc",
          "displayName": "Traversal PoC",
          "format": "onnxTokenClassification",
          "files": [
            {
              "url": "\(payload.absoluteString)",
              "path": "../../escape.txt"
            }
          ]
        }
        """
        try Data(manifestJSON.utf8).write(to: manifestURL)

        let importer = ManifestModelImporter()
        do {
            _ = try await importer.importModel(
                reference: .manifest(manifestURL),
                into: modelDirectory,
                credentials: AIModelCredentials(),
                progress: { _ in }
            )
            XCTFail("Expected import to fail for traversal path")
        } catch let error as AIModelCatalogError {
            guard case .importFailed(let message) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertTrue(
                message.contains("escapes the model directory"),
                "Unexpected failure message: \(message)"
            )
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }

        XCTAssertFalse(
            FileManager.default.fileExists(atPath: escapeTarget.path),
            "Traversal path must not write outside the model directory"
        )
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: modelDirectory.appendingPathComponent("escape.txt").path)
        )
    }

    func testImportRejectsUnsafeModelIDBeforeWriting() async throws {
        let payload = tempRoot.appendingPathComponent("payload.txt")
        try Data("pwned".utf8).write(to: payload)

        let modelDirectory = tempRoot.appendingPathComponent("Models/poc", isDirectory: true)
        try FileManager.default.createDirectory(at: modelDirectory, withIntermediateDirectories: true)

        let manifestURL = tempRoot.appendingPathComponent("manifest.json")
        let manifestJSON = """
        {
          "id": "../escape-id",
          "displayName": "Bad ID",
          "format": "onnxTokenClassification",
          "files": [
            {
              "url": "\(payload.absoluteString)",
              "path": "model.onnx"
            }
          ]
        }
        """
        try Data(manifestJSON.utf8).write(to: manifestURL)

        let importer = ManifestModelImporter()
        do {
            _ = try await importer.importModel(
                reference: .manifest(manifestURL),
                into: modelDirectory,
                credentials: AIModelCredentials(),
                progress: { _ in }
            )
            XCTFail("Expected import to fail for unsafe model id")
        } catch let error as AIModelCatalogError {
            guard case .importFailed(let message) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertTrue(
                message.contains("safe directory name"),
                "Unexpected failure message: \(message)"
            )
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }

        XCTAssertFalse(
            FileManager.default.fileExists(atPath: modelDirectory.appendingPathComponent("model.onnx").path),
            "No files should be written when the model id is unsafe"
        )
    }
}
