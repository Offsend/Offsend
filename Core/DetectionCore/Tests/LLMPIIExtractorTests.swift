import XCTest
@testable import DetectionCore

final class LLMPIIExtractorTests: XCTestCase {
    func testParsesEntitiesFromJSON() {
        let text = "Contact John Doe at john@acme.com"
        let json = """
        {"entities":[{"type":"PERSON","text":"John Doe"},{"type":"EMAIL","text":"john@acme.com"}]}
        """
        let entities = LLMPIIExtractor.parseEntities(
            jsonText: json,
            in: text,
            options: .default
        )
        let types = Set(entities.map(\.type))
        XCTAssertTrue(types.contains(.personName))
        XCTAssertTrue(types.contains(.email))
    }

    func testRemapsChunkOffsetsIntoParentText() {
        let text = "prefix " + String(repeating: "x", count: 4_100) + " secret@acme.com"
        let chunks = LLMPIIExtractor.chunkText(text)
        XCTAssertGreaterThan(chunks.count, 1)

        guard let last = chunks.last else {
            return XCTFail("Expected multiple chunks")
        }
        let local = LLMPIIExtractor.parseEntities(
            jsonText: #"{"entities":[{"type":"EMAIL","text":"secret@acme.com"}]}"#,
            in: last.substring,
            options: .default
        )
        let remapped = LLMPIIExtractor.remap(local, chunk: last, in: text)
        XCTAssertEqual(remapped.first?.value, "secret@acme.com")
        XCTAssertEqual(String(text[remapped.first!.range]), "secret@acme.com")
    }

    func testRemapsNonASCIIChunkOffsetsWithoutDrift() {
        let text = "Привет " + String(repeating: "д", count: 4_100) + " контакт: ivan@acme.ru"
        let chunks = LLMPIIExtractor.chunkText(text)
        XCTAssertGreaterThan(chunks.count, 1)

        guard let last = chunks.last else {
            return XCTFail("Expected multiple chunks")
        }
        let local = LLMPIIExtractor.parseEntities(
            jsonText: #"{"entities":[{"type":"EMAIL","text":"ivan@acme.ru"}]}"#,
            in: last.substring,
            options: .default
        )
        let remapped = LLMPIIExtractor.remap(local, chunk: last, in: text)
        XCTAssertEqual(remapped.first.map { String(text[$0.range]) }, "ivan@acme.ru")
    }
}
