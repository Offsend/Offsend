import XCTest
@testable import DetectionCore

final class InstalledAIModelMigrationTests: XCTestCase {
    func testDecodesLegacyRepositoryIDFormat() throws {
        let json = """
        {
            "repositoryID": "author/model",
            "displayName": "Test Model",
            "revision": "main",
            "downloadedAt": "2024-01-01T00:00:00Z",
            "totalByteSize": 1000
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let model = try decoder.decode(InstalledAIModel.self, from: json)

        XCTAssertEqual(model.id, "author/model")
        XCTAssertEqual(model.source, .huggingFace(repositoryID: "author/model", revision: "main"))
        XCTAssertEqual(model.localDirectoryName, "author__model")
    }

    func testEncodesNewFormat() throws {
        let model = InstalledAIModel(
            id: "test-id",
            displayName: "Test",
            source: .importedFolder(originalPath: "/tmp/model"),
            format: .onnxTokenClassification,
            localDirectoryName: "test-id"
        )
        let data = try JSONEncoder().encode(model)
        let decoded = try JSONDecoder().decode(InstalledAIModel.self, from: data)
        XCTAssertEqual(decoded, model)
    }
}
