import XCTest
@testable import DetectionCore

final class TokenClassificationDecoderTests: XCTestCase {
    func testChunkedDetectionRemapsEntityRangesIntoParentText() throws {
        let tokenizer = try makeWordPieceTokenizer()
        let config = HFModelConfig(id2label: [0: "O", 1: "B-PER"], maxPositionEmbeddings: 512)
        let text = String(repeating: "x", count: 1_600) + " amy " + String(repeating: "y", count: 501)

        let entities = try TokenClassificationDecoder.detect(
            text: text,
            tokenizer: tokenizer,
            config: config,
            options: DetectionOptions(enabledTypes: [.personName], aiDetectionEnabled: true),
            maxLength: TokenClassificationDecoder.defaultMaxLength
        ) { tokens in
            let labelCount = 2
            var logits = [Float](repeating: 0, count: tokens.count * labelCount)
            for (index, token) in tokens.enumerated() {
                let offset = index * labelCount
                if token.piece.lowercased().contains("amy") {
                    logits[offset + 1] = 10
                } else {
                    logits[offset] = 10
                }
            }
            return logits
        }

        XCTAssertEqual(entities.count, 1)
        XCTAssertEqual(entities.first?.value, "amy")
        XCTAssertEqual(String(text[entities.first!.range]), "amy")
        XCTAssertEqual(text.distance(from: text.startIndex, to: entities.first!.range.lowerBound), 1_601)
    }

    func testSubwordContinuationExtendsEntitySpan() throws {
        let tokenizer = try makeSubwordTokenizer()
        let config = HFModelConfig(id2label: [0: "O", 1: "B-PER"], maxPositionEmbeddings: 512)

        let entities = try TokenClassificationDecoder.detect(
            text: "amys",
            tokenizer: tokenizer,
            config: config,
            options: DetectionOptions(enabledTypes: [.personName], aiDetectionEnabled: true),
            maxLength: TokenClassificationDecoder.defaultMaxLength
        ) { tokens in
            let labelCount = 2
            var logits = [Float](repeating: 0, count: tokens.count * labelCount)
            for (index, token) in tokens.enumerated() {
                let offset = index * labelCount
                // Only the first subword ("amy") is labelled PER; the tail "##s" is left O on purpose.
                if token.piece == "amy" {
                    logits[offset + 1] = 10
                } else {
                    logits[offset] = 10
                }
            }
            return logits
        }

        XCTAssertEqual(entities.count, 1)
        XCTAssertEqual(entities.first?.value, "amys", "Tail subword should inherit the word's entity, not get cut.")
    }

    func testLowConfidenceSpansAreDropped() throws {
        let tokenizer = try makeWordPieceTokenizer()
        let config = HFModelConfig(id2label: [0: "O", 1: "B-PER", 2: "B-LOC"], maxPositionEmbeddings: 512)

        let entities = try TokenClassificationDecoder.detect(
            text: "amy",
            tokenizer: tokenizer,
            config: config,
            options: DetectionOptions(enabledTypes: [.personName], aiDetectionEnabled: true),
            maxLength: TokenClassificationDecoder.defaultMaxLength
        ) { tokens in
            let labelCount = 3
            var logits = [Float](repeating: 0, count: tokens.count * labelCount)
            for (index, token) in tokens.enumerated() where token.piece == "amy" {
                // argmax → B-PER, but 3-way softmax ≈ 0.36 stays below the confidence floor.
                logits[index * labelCount + 1] = 0.1
            }
            return logits
        }

        XCTAssertTrue(entities.isEmpty, "Spans below the softmax confidence floor must be discarded.")
    }

    func testMergesOverlappingSameTypeSpansFromAdjacentWindows() {
        let text = "John Smith lives here"
        let johnSmith = text.range(of: "John Smith")!
        let smith = text.range(of: "Smith")!

        // The same person truncated differently by two windows.
        let full = SensitiveEntity(type: .personName, range: johnSmith, value: "John Smith", confidence: 0.9, source: .ai)
        let clipped = SensitiveEntity(type: .personName, range: smith, value: "Smith", confidence: 0.6, source: .ai)

        let merged = TokenClassificationDecoder.mergeWindowOverlaps([clipped, full], in: text)

        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged.first?.value, "John Smith")
        XCTAssertEqual(merged.first?.confidence, 0.9, "The window that saw the entity whole should win")
    }

    func testKeepsOverlappingSpansOfDifferentTypes() {
        let text = "John Smith"
        let full = text.startIndex..<text.endIndex
        let person = SensitiveEntity(type: .personName, range: full, value: text, confidence: 0.9, source: .ai)
        let address = SensitiveEntity(type: .streetAddress, range: full, value: text, confidence: 0.8, source: .ai)

        let merged = TokenClassificationDecoder.mergeWindowOverlaps([person, address], in: text)

        XCTAssertEqual(merged.count, 2, "Cross-type overlaps are resolved later by OverlapResolver")
    }

    func testKeepsDisjointSameTypeSpansSeparate() {
        let text = "John met Anna"
        let john = text.range(of: "John")!
        let anna = text.range(of: "Anna")!
        let first = SensitiveEntity(type: .personName, range: john, value: "John", confidence: 0.9, source: .ai)
        let second = SensitiveEntity(type: .personName, range: anna, value: "Anna", confidence: 0.9, source: .ai)

        let merged = TokenClassificationDecoder.mergeWindowOverlaps([first, second], in: text)

        XCTAssertEqual(merged.map(\.value), ["John", "Anna"])
    }

    func testExactDuplicateSpansCollapseToOne() {
        let text = "John"
        let range = text.startIndex..<text.endIndex
        let a = SensitiveEntity(type: .personName, range: range, value: text, confidence: 0.9, source: .ai)
        let b = SensitiveEntity(type: .personName, range: range, value: text, confidence: 0.9, source: .ai)

        let merged = TokenClassificationDecoder.mergeWindowOverlaps([a, b], in: text)

        XCTAssertEqual(merged.count, 1)
    }

    private func makeSubwordTokenizer() throws -> HFTokenizer {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let tokenizerURL = directory.appendingPathComponent("tokenizer.json")
        let json = """
        {
          "model": {
            "type": "WordPiece",
            "unk_token": "[UNK]",
            "continuing_subword_prefix": "##",
            "vocab": {
              "[PAD]": 0,
              "[UNK]": 1,
              "[CLS]": 2,
              "[SEP]": 3,
              "amy": 4,
              "##s": 5
            }
          }
        }
        """
        try json.write(to: tokenizerURL, atomically: true, encoding: .utf8)
        return try HFTokenizer(tokenizerURL: tokenizerURL)
    }

    private func makeWordPieceTokenizer() throws -> HFTokenizer {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let tokenizerURL = directory.appendingPathComponent("tokenizer.json")
        let json = """
        {
          "model": {
            "type": "WordPiece",
            "unk_token": "[UNK]",
            "continuing_subword_prefix": "##",
            "vocab": {
              "[PAD]": 0,
              "[UNK]": 1,
              "[CLS]": 2,
              "[SEP]": 3,
              "amy": 4,
              "x": 5,
              "y": 6,
              " ": 7
            }
          }
        }
        """
        try json.write(to: tokenizerURL, atomically: true, encoding: .utf8)
        return try HFTokenizer(tokenizerURL: tokenizerURL)
    }
}
