import Foundation
import XCTest
@testable import DocumentCore

final class DocumentPrepareSelectionClassifierTests: XCTestCase {
    private var temporaryURLs: [URL] = []

    override func tearDown() {
        for url in temporaryURLs {
            try? FileManager.default.removeItem(at: url)
        }
        temporaryURLs.removeAll()
        super.tearDown()
    }

    func testSingleSupportedFileReturnsDocuments() throws {
        let fileURL = try makeTemporaryTextFile(named: "invoice.txt")

        let selection = DocumentPrepareSelectionClassifier.selection(for: fileURL)

        XCTAssertEqual(selection, .documents([fileURL.standardizedFileURL]))
    }

    func testMultipleSupportedFilesReturnsDocumentsInOrder() throws {
        let first = try makeTemporaryTextFile(named: "first.txt")
        let second = try makeTemporaryTextFile(named: "second.txt")

        let selection = DocumentPrepareSelectionClassifier.selection(forMultiple: [first, second])

        XCTAssertEqual(selection, .documents([first.standardizedFileURL, second.standardizedFileURL]))
    }

    func testDirectoryTakesPriorityOverFiles() throws {
        let directoryURL = try makeTemporaryDirectory()
        let fileURL = try makeTemporaryTextFile(named: "notes.txt", in: directoryURL)

        let selection = DocumentPrepareSelectionClassifier.selection(forMultiple: [fileURL, directoryURL])

        XCTAssertEqual(selection, .directory(directoryURL.standardizedFileURL))
    }

    func testUnsupportedFilesAreFilteredOut() throws {
        let supported = try makeTemporaryTextFile(named: "supported.txt")
        let unsupported = try makeTemporaryFile(
            named: "image.png",
            contents: Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        )

        let selection = DocumentPrepareSelectionClassifier.selection(forMultiple: [unsupported, supported])

        XCTAssertEqual(selection, .documents([supported.standardizedFileURL]))
    }

    func testEmptySelectionReturnsNil() {
        XCTAssertNil(DocumentPrepareSelectionClassifier.selection(forMultiple: []))
    }

    func testDuplicateFilesAreRemoved() throws {
        let fileURL = try makeTemporaryTextFile(named: "duplicate.txt")

        let selection = DocumentPrepareSelectionClassifier.selection(forMultiple: [fileURL, fileURL])

        XCTAssertEqual(selection, .documents([fileURL.standardizedFileURL]))
    }

    func testAllUnsupportedSelectionReturnsNil() throws {
        let unsupported = try makeTemporaryFile(
            named: "image.png",
            contents: Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        )

        XCTAssertNil(DocumentPrepareSelectionClassifier.selection(forMultiple: [unsupported]))
    }

    @discardableResult
    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("prepare-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        temporaryURLs.append(url)
        return url
    }

    @discardableResult
    private func makeTemporaryTextFile(named name: String, in directory: URL? = nil) throws -> URL {
        let baseDirectory = directory ?? FileManager.default.temporaryDirectory
        let url = baseDirectory.appendingPathComponent("\(UUID().uuidString)-\(name)")
        try "Sample text".write(to: url, atomically: true, encoding: .utf8)
        if directory == nil {
            temporaryURLs.append(url)
        }
        return url
    }

    @discardableResult
    private func makeTemporaryFile(named name: String, contents: Data) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString)-\(name)")
        try contents.write(to: url)
        temporaryURLs.append(url)
        return url
    }
}
