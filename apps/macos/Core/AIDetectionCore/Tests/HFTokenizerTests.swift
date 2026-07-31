import XCTest
import DetectionCore
@testable import AIDetectionCore

final class HFTokenizerTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDirectory)
    }

    func testWordPieceTokenizerEncodesSimpleText() throws {
        let tokenizerURL = tempDirectory.appendingPathComponent("tokenizer.json")
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
              "hello": 4,
              "world": 5,
              "##world": 6
            }
          }
        }
        """
        try json.write(to: tokenizerURL, atomically: true, encoding: .utf8)

        let tokenizer = try HFTokenizer(tokenizerURL: tokenizerURL)
        let tokens = tokenizer.encode(text: "hello world", maxLength: 16)

        XCTAssertEqual(tokens.first?.id, 2)
        XCTAssertEqual(tokens.last?.id, 3)
        XCTAssertTrue(tokens.contains { $0.piece == "hello" })
    }

    func testWordPieceMarksUntokenizableWordAsUNKWithFullWordRange() throws {
        let tokenizerURL = tempDirectory.appendingPathComponent("tokenizer.json")
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
              "amy": 4
            }
          }
        }
        """
        try json.write(to: tokenizerURL, atomically: true, encoding: .utf8)

        let tokenizer = try HFTokenizer(tokenizerURL: tokenizerURL)
        let text = "amy zzz"
        let tokens = tokenizer.encode(text: text, maxLength: 16)

        let unk = tokens.first { $0.id == 1 && !$0.isSpecial }
        XCTAssertNotNil(unk, "Untokenizable word must surface as [UNK], not vanish")
        XCTAssertEqual(unk?.range.map { String(text[$0]) }, "zzz", "[UNK] must keep the whole word's range")
    }

    func testWordPiecePartialSubwordFailureCollapsesWholeWordToUNK() throws {
        let tokenizerURL = tempDirectory.appendingPathComponent("tokenizer.json")
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
              "amy": 4
            }
          }
        }
        """
        try json.write(to: tokenizerURL, atomically: true, encoding: .utf8)

        let tokenizer = try HFTokenizer(tokenizerURL: tokenizerURL)
        let text = "amyzzz"
        let tokens = tokenizer.encode(text: text, maxLength: 16)
        let content = tokens.filter { !$0.isSpecial }

        // HF WordPiece semantics: if any piece of a word fails, the whole word is one [UNK].
        XCTAssertEqual(content.count, 1)
        XCTAssertEqual(content.first?.id, 1)
        XCTAssertEqual(content.first?.range.map { String(text[$0]) }, "amyzzz")
    }

    func testResolveURLPrefersTokenizerJSONOverConfigHint() throws {
        let configURL = tempDirectory.appendingPathComponent("tokenizer_config.json")
        let tokenizerURL = tempDirectory.appendingPathComponent("tokenizer.json")
        try Data("{}".utf8).write(to: configURL)
        try Data(#"{"model":{"type":"WordPiece","vocab":{"a":0}}}"#.utf8).write(to: tokenizerURL)

        let resolved = HFTokenizer.resolveURL(in: tempDirectory, hint: "tokenizer_config.json")
        XCTAssertEqual(resolved.lastPathComponent, "tokenizer.json")
    }

    func testUnigramTokenizerEncodesLikeXLMRoberta() throws {
        let installedURL = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("Offsend/Models/onnx-community__multilang-pii-ner-ONNX/tokenizer.json")
        let fallbackURL = URL(fileURLWithPath: "/tmp/multilang-tokenizer.json")
        let tokenizerURL: URL
        if FileManager.default.fileExists(atPath: installedURL.path) {
            tokenizerURL = installedURL
        } else if FileManager.default.fileExists(atPath: fallbackURL.path) {
            tokenizerURL = fallbackURL
        } else {
            throw XCTSkip("Multilingual PII NER tokenizer.json is not available locally.")
        }

        let resolved = HFTokenizer.resolveURL(
            in: tokenizerURL.deletingLastPathComponent(),
            hint: "tokenizer_config.json"
        )
        XCTAssertEqual(resolved.lastPathComponent, "tokenizer.json")

        let tokenizer = try HFTokenizer(tokenizerURL: resolved)
        let hello = tokenizer.encode(text: "hello", maxLength: 16)
        XCTAssertEqual(hello.map(\.id), [0, 33_600, 31, 2])

        let sentence = tokenizer.encode(text: "John lives in Berlin", maxLength: 32)
        XCTAssertEqual(sentence.map(\.id), [0, 4_939, 60_742, 23, 10_271, 2])
        XCTAssertEqual(sentence.map(\.piece), ["<s>", "▁John", "▁lives", "▁in", "▁Berlin", "</s>"])
    }

    func testParsesBPEMergesInNewArrayFormat() throws {
        let tokenizerURL = tempDirectory.appendingPathComponent("tokenizer.json")
        // tokenizers >= 0.20 serializes merges as [["a", "b"], ...] instead of ["a b", ...].
        let json = """
        {
          "model": {
            "type": "BPE",
            "unk_token": "[UNK]",
            "vocab": { "[UNK]": 0, "a": 1, "b": 2, "ab": 3 },
            "merges": [["a", "b"]]
          }
        }
        """
        try json.write(to: tokenizerURL, atomically: true, encoding: .utf8)

        let tokenizer = try HFTokenizer(tokenizerURL: tokenizerURL)
        let tokens = tokenizer.encode(text: "ab", maxLength: 8)
        XCTAssertTrue(tokens.contains { $0.piece == "ab" && $0.id == 3 }, "Merges in array format must be applied.")
    }

    func testRejectsByteLevelBPETokenizer() throws {
        let tokenizerURL = tempDirectory.appendingPathComponent("tokenizer.json")
        let json = """
        {
          "pre_tokenizer": { "type": "ByteLevel", "add_prefix_space": false },
          "model": {
            "type": "BPE",
            "vocab": { "Ġhello": 0, "world": 1 },
            "merges": []
          }
        }
        """
        try json.write(to: tokenizerURL, atomically: true, encoding: .utf8)

        XCTAssertThrowsError(try HFTokenizer(tokenizerURL: tokenizerURL)) { error in
            XCTAssertEqual(error as? HFTokenizerError, .byteLevelBPEUnsupported)
        }
    }

    func testLowercasesInputForUncasedVocabLookup() throws {
        let tokenizerURL = tempDirectory.appendingPathComponent("tokenizer.json")
        let json = """
        {
          "normalizer": { "type": "BertNormalizer", "lowercase": true, "strip_accents": false },
          "model": {
            "type": "WordPiece",
            "unk_token": "[UNK]",
            "continuing_subword_prefix": "##",
            "vocab": {
              "[PAD]": 0,
              "[UNK]": 1,
              "[CLS]": 2,
              "[SEP]": 3,
              "john": 4
            }
          }
        }
        """
        try json.write(to: tokenizerURL, atomically: true, encoding: .utf8)

        let tokenizer = try HFTokenizer(tokenizerURL: tokenizerURL)
        let tokens = tokenizer.encode(text: "John", maxLength: 16)
        XCTAssertTrue(tokens.contains { $0.id == 4 }, "Uncased model should match lowercased vocab entry, not [UNK].")
    }

    func testModelConfigParsesId2Label() throws {
        let configURL = tempDirectory.appendingPathComponent("config.json")
        let json = """
        {
          "id2label": { "0": "O", "1": "B-PER", "2": "I-PER" },
          "max_position_embeddings": 128
        }
        """
        try json.write(to: configURL, atomically: true, encoding: .utf8)

        let config = HFModelConfig.load(from: tempDirectory)
        XCTAssertEqual(config?.id2label[1], "B-PER")
        XCTAssertEqual(config?.maxPositionEmbeddings, 128)
    }
}
