import XCTest
import DetectionCore
@testable import AIDetectionCore

final class AIModelImportCoordinatorTests: XCTestCase {
    func testFailedImportRemovesProvisionalDirectory() async throws {
        let modelsRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("offsend-ai-import-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: modelsRoot, withIntermediateDirectories: true)
        let previous = AIModelFileStore.modelsDirectoryOverrideForTesting
        AIModelFileStore.modelsDirectoryOverrideForTesting = modelsRoot
        defer {
            AIModelFileStore.modelsDirectoryOverrideForTesting = previous
            try? FileManager.default.removeItem(at: modelsRoot)
        }

        let coordinator = AIModelImportCoordinator(importers: [FailingImporter()])
        let reference = AIModelImportReference.remoteURL(URL(string: "https://example.com/model.onnx")!)

        do {
            _ = try await coordinator.importModel(reference: reference) { _ in }
            XCTFail("Expected import to fail")
        } catch {
            // Expected
        }

        let leftovers = try FileManager.default.contentsOfDirectory(
            at: modelsRoot,
            includingPropertiesForKeys: nil
        )
        XCTAssertTrue(leftovers.isEmpty, "Failed import must not leave orphan model directories")
    }
}

private struct FailingImporter: AIModelImporting {
    func canHandle(_ reference: AIModelImportReference) -> Bool {
        if case .remoteURL = reference { return true }
        return false
    }

    func importModel(
        reference: AIModelImportReference,
        into directory: URL,
        credentials: AIModelCredentials,
        progress: @escaping @Sendable (AIModelDownloadProgress) -> Void
    ) async throws -> AIModelImportResult {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("partial".utf8).write(to: directory.appendingPathComponent("partial.bin"))
        throw AIModelCatalogError.importFailed("boom")
    }
}
