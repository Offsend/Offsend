import Foundation

public struct HFEncodedToken: Equatable, Sendable {
    public let id: Int64
    public let piece: String
    public let range: Range<String.Index>?
    public let isSpecial: Bool
    /// True for subword pieces that continue the previous token's word (`##xxx`, non word-initial BPE/Unigram pieces).
    public let isContinuation: Bool

    public init(
        id: Int64,
        piece: String,
        range: Range<String.Index>? = nil,
        isSpecial: Bool = false,
        isContinuation: Bool = false
    ) {
        self.id = id
        self.piece = piece
        self.range = range
        self.isSpecial = isSpecial
        self.isContinuation = isContinuation
    }
}

public enum HFTokenizerError: Error, Equatable, Sendable {
    case unsupportedFormat
    case missingVocabulary
    case fileNotFound(String)
    case byteLevelBPEUnsupported
}

extension HFTokenizerError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .unsupportedFormat:
            return "Unsupported Hugging Face tokenizer format."
        case .missingVocabulary:
            return "Tokenizer vocabulary is missing."
        case .fileNotFound(let name):
            return "Tokenizer file not found: \(name)."
        case .byteLevelBPEUnsupported:
            return "Byte-level BPE tokenizers (RoBERTa / GPT-2 family) are not supported. Use a WordPiece (BERT) or SentencePiece/Unigram (DeBERTa, XLM-R) token-classification model."
        }
    }
}

/// Minimal Hugging Face `tokenizer.json` loader (WordPiece, BPE, Unigram).
public struct HFTokenizer: Sendable {
    public enum ModelKind: Sendable {
        case wordPiece(continuingPrefix: String)
        case bpe(merges: [(String, String)])
        case unigram(scores: [String: Double], unknownScore: Double, metaspaceReplacement: String)
    }

    private let vocab: [String: Int64]
    private let reverseVocab: [Int64: String]
    private let kind: ModelKind
    private let unkTokenId: Int64
    private let clsTokenId: Int64
    private let sepTokenId: Int64
    private let padTokenId: Int64
    private let addedTokenIDs: Set<Int64>
    private let lowercaseInput: Bool
    private let stripAccents: Bool

    public static func resolveURL(in directory: URL, hint: String? = nil) -> URL {
        if let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil) {
            for case let file as URL in enumerator where file.lastPathComponent == "tokenizer.json" {
                return file
            }
        }

        let defaultURL = directory.appendingPathComponent("tokenizer.json")
        if FileManager.default.fileExists(atPath: defaultURL.path) {
            return defaultURL
        }

        if let hint {
            let hinted = directory.appendingPathComponent(hint)
            if FileManager.default.fileExists(atPath: hinted.path) {
                return hinted
            }
        }

        return defaultURL
    }

    public init(tokenizerURL: URL) throws {
        guard FileManager.default.fileExists(atPath: tokenizerURL.path) else {
            throw HFTokenizerError.fileNotFound(tokenizerURL.lastPathComponent)
        }
        let data = try Data(contentsOf: tokenizerURL)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let model = json?["model"] as? [String: Any],
              let type = model["type"] as? String else {
            throw HFTokenizerError.unsupportedFormat
        }

        var vocabMap: [String: Int64] = [:]
        var scoreMap: [String: Double] = [:]

        switch type {
        case "Unigram":
            guard let rawVocabList = model["vocab"] as? [[Any]] else {
                throw HFTokenizerError.unsupportedFormat
            }
            for (index, entry) in rawVocabList.enumerated() {
                guard entry.count >= 2,
                      let token = entry[0] as? String,
                      let score = Self.jsonNumber(entry[1]) else {
                    continue
                }
                vocabMap[token] = Int64(index)
                scoreMap[token] = score
            }
        default:
            guard let rawVocab = model["vocab"] as? [String: Int] else {
                throw HFTokenizerError.unsupportedFormat
            }
            for (token, id) in rawVocab {
                vocabMap[token] = Int64(id)
            }
        }

        guard !vocabMap.isEmpty else { throw HFTokenizerError.missingVocabulary }

        self.vocab = vocabMap
        var reverse: [Int64: String] = [:]
        for (token, id) in vocabMap {
            reverse[id] = token
        }
        self.reverseVocab = reverse

        switch type {
        case "WordPiece":
            let prefix = model["continuing_subword_prefix"] as? String ?? "##"
            self.kind = .wordPiece(continuingPrefix: prefix)
        case "BPE":
            // Byte-level BPE (RoBERTa/GPT-2) needs a byte→unicode map and produces offsets we
            // cannot map back to exact spans here; reject instead of emitting garbage detections.
            if Self.usesByteLevel(json: json) {
                throw HFTokenizerError.byteLevelBPEUnsupported
            }
            self.kind = .bpe(merges: Self.parseMerges(model["merges"]))
        case "Unigram":
            let minScore = scoreMap.values.min() ?? 0
            let metaspaceReplacement = Self.metaspaceReplacement(from: json)
            self.kind = .unigram(
                scores: scoreMap,
                unknownScore: minScore - 10,
                metaspaceReplacement: metaspaceReplacement
            )
        default:
            throw HFTokenizerError.unsupportedFormat
        }

        var addedIDs = Set<Int64>()
        if let added = json?["added_tokens"] as? [[String: Any]] {
            for entry in added {
                if let id = entry["id"] as? Int {
                    addedIDs.insert(Int64(id))
                }
            }
        }
        self.addedTokenIDs = addedIDs

        if type == "Unigram" {
            self.unkTokenId = Int64(model["unk_id"] as? Int ?? 3)
            self.clsTokenId = vocabMap["<s>"] ?? vocabMap["[CLS]"] ?? 0
            self.sepTokenId = vocabMap["</s>"] ?? vocabMap["[SEP]"] ?? 2
            self.padTokenId = vocabMap["<pad>"] ?? vocabMap["[PAD]"] ?? 1
        } else {
            let unk = model["unk_token"] as? String ?? "[UNK]"
            self.unkTokenId = vocabMap[unk] ?? 100
            self.clsTokenId = vocabMap["[CLS]"] ?? vocabMap["<s>"] ?? 101
            self.sepTokenId = vocabMap["[SEP]"] ?? vocabMap["</s>"] ?? 102
            self.padTokenId = vocabMap["[PAD]"] ?? vocabMap["<pad>"] ?? 0
        }

        // Unigram/SentencePiece carries normalization in a precompiled charsmap we do not replay;
        // case folding is applied only to WordPiece/BPE vocab lookups, where uncased models matter.
        let normalization = type == "Unigram" ? (false, false) : Self.parseNormalization(from: json)
        self.lowercaseInput = normalization.0
        self.stripAccents = normalization.1
    }

    private func normalizedKey(_ piece: String) -> String {
        guard lowercaseInput || stripAccents else { return piece }
        var key = piece
        if lowercaseInput { key = key.lowercased() }
        if stripAccents { key = key.folding(options: .diacriticInsensitive, locale: nil) }
        return key
    }

    private static func parseNormalization(from json: [String: Any]?) -> (lowercase: Bool, stripAccents: Bool) {
        guard let normalizer = json?["normalizer"] else { return (false, false) }
        return scanNormalizer(normalizer)
    }

    private static func scanNormalizer(_ node: Any) -> (lowercase: Bool, stripAccents: Bool) {
        guard let node = node as? [String: Any], let type = node["type"] as? String else {
            return (false, false)
        }
        switch type {
        case "Lowercase":
            return (true, false)
        case "StripAccents", "NFD", "NFKD":
            return (false, true)
        case "BertNormalizer":
            let lowercase = node["lowercase"] as? Bool ?? true
            // `strip_accents` is often null in BertNormalizer, meaning "follow lowercase".
            let strip = node["strip_accents"] as? Bool ?? lowercase
            return (lowercase, strip)
        case "Sequence":
            var lowercase = false
            var strip = false
            for child in node["normalizers"] as? [Any] ?? [] {
                let result = scanNormalizer(child)
                lowercase = lowercase || result.lowercase
                strip = strip || result.stripAccents
            }
            return (lowercase, strip)
        default:
            return (false, false)
        }
    }

    /// tokenizers < 0.20 serializes merges as `["a b", ...]`; newer versions emit `[["a", "b"], ...]`.
    private static func parseMerges(_ raw: Any?) -> [(String, String)] {
        if let mergeLines = raw as? [String] {
            return mergeLines.compactMap { line in
                let parts = line.split(separator: " ", maxSplits: 1).map(String.init)
                return parts.count == 2 ? (parts[0], parts[1]) : nil
            }
        }
        if let mergePairs = raw as? [[String]] {
            return mergePairs.compactMap { pair in
                pair.count == 2 ? (pair[0], pair[1]) : nil
            }
        }
        return []
    }

    private static func usesByteLevel(json: [String: Any]?) -> Bool {
        func mentionsByteLevel(_ node: Any?) -> Bool {
            guard let node = node as? [String: Any] else { return false }
            if (node["type"] as? String) == "ByteLevel" { return true }
            if let nested = node["pretokenizers"] as? [Any], nested.contains(where: { mentionsByteLevel($0) }) {
                return true
            }
            return false
        }
        return mentionsByteLevel(json?["pre_tokenizer"]) || mentionsByteLevel(json?["decoder"])
    }

    public func encode(text: String, maxLength: Int, addSpecialTokens: Bool = true) -> [HFEncodedToken] {
        var tokens: [HFEncodedToken] = []
        if addSpecialTokens {
            tokens.append(HFEncodedToken(id: clsTokenId, piece: reverseVocab[clsTokenId] ?? "[CLS]", isSpecial: true))
        }

        switch kind {
        case .unigram(let scores, let unknownScore, let metaspaceReplacement):
            for word in metaspaceWords(in: text, replacement: metaspaceReplacement) {
                let pieces = unigramSegment(word.metaspaceText, scores: scores, unknownScore: unknownScore)
                var offset = 0
                for (pieceIndex, piece) in pieces.enumerated() {
                    let isUNK = piece == (reverseVocab[unkTokenId] ?? "<unk>")
                    let range = pieceRange(
                        piece: piece,
                        text: text,
                        in: word,
                        metaspaceReplacement: metaspaceReplacement,
                        offset: &offset,
                        isUNK: isUNK
                    )
                    let tokenID = isUNK ? unkTokenId : (vocab[piece] ?? unkTokenId)
                    tokens.append(HFEncodedToken(id: tokenID, piece: piece, range: range, isContinuation: pieceIndex > 0))
                }
            }
        default:
            for span in pretokenSpans(in: text) {
                let pieces: [(String, Range<String.Index>)]
                switch kind {
                case .wordPiece(let prefix):
                    pieces = wordPiece(text: text, in: span.range, prefix: prefix)
                case .bpe(let merges):
                    pieces = bpe(text: text, in: span.range, merges: merges)
                case .unigram:
                    pieces = []
                }
                for (pieceIndex, entry) in pieces.enumerated() {
                    tokens.append(
                        HFEncodedToken(
                            id: vocab[normalizedKey(entry.0)] ?? unkTokenId,
                            piece: entry.0,
                            range: entry.1,
                            isContinuation: pieceIndex > 0
                        )
                    )
                }
            }
        }

        if addSpecialTokens {
            tokens.append(HFEncodedToken(id: sepTokenId, piece: reverseVocab[sepTokenId] ?? "[SEP]", isSpecial: true))
        }

        if tokens.count > maxLength {
            var truncated = Array(tokens.prefix(maxLength - 1))
            truncated.append(HFEncodedToken(id: sepTokenId, piece: reverseVocab[sepTokenId] ?? "[SEP]", isSpecial: true))
            return truncated
        }
        return tokens
    }

    public func pad(_ tokens: [HFEncodedToken], to length: Int) -> [HFEncodedToken] {
        guard tokens.count < length else { return tokens }
        var padded = tokens
        let padPiece = reverseVocab[padTokenId] ?? ""
        while padded.count < length {
            padded.append(HFEncodedToken(id: padTokenId, piece: padPiece, isSpecial: true))
        }
        return padded
    }

    public var padToken: Int64 { padTokenId }

    /// Content tokens (no `[CLS]`/`[SEP]`) with ranges into `text`, used for token-windowed chunking.
    public func encodeContentTokens(text: String) -> [HFEncodedToken] {
        encode(text: text, maxLength: Int.max, addSpecialTokens: false)
    }

    public var classifierStartToken: HFEncodedToken {
        HFEncodedToken(id: clsTokenId, piece: reverseVocab[clsTokenId] ?? "[CLS]", isSpecial: true)
    }

    public var separatorToken: HFEncodedToken {
        HFEncodedToken(id: sepTokenId, piece: reverseVocab[sepTokenId] ?? "[SEP]", isSpecial: true)
    }

    private struct PretokenSpan {
        let text: String
        let range: Range<String.Index>
    }

    private struct MetaspaceWord {
        let metaspaceText: String
        let range: Range<String.Index>
    }

    private static func jsonNumber(_ value: Any) -> Double? {
        if let number = value as? NSNumber {
            return number.doubleValue
        }
        if let value = value as? Double {
            return value
        }
        if let value = value as? Int {
            return Double(value)
        }
        return nil
    }

    private static func metaspaceReplacement(from json: [String: Any]?) -> String {
        guard let preTokenizer = json?["pre_tokenizer"] as? [String: Any] else {
            return "▁"
        }
        if let pretokenizers = preTokenizer["pretokenizers"] as? [[String: Any]] {
            for pretokenizer in pretokenizers where pretokenizer["type"] as? String == "Metaspace" {
                return pretokenizer["replacement"] as? String ?? "▁"
            }
        }
        return "▁"
    }

    private func metaspaceWords(in text: String, replacement: String) -> [MetaspaceWord] {
        guard !text.isEmpty else { return [] }
        var words: [MetaspaceWord] = []
        var index = text.startIndex
        while index < text.endIndex {
            while index < text.endIndex, text[index].isWhitespace {
                index = text.index(after: index)
            }
            guard index < text.endIndex else { break }

            let start = index
            while index < text.endIndex, !text[index].isWhitespace {
                index = text.index(after: index)
            }
            let range = start..<index
            words.append(MetaspaceWord(metaspaceText: replacement + String(text[range]), range: range))
        }
        return words
    }

    private func pieceRange(
        piece: String,
        text: String,
        in word: MetaspaceWord,
        metaspaceReplacement: String,
        offset: inout Int,
        isUNK: Bool
    ) -> Range<String.Index>? {
        if isUNK {
            guard let pieceStart = index(in: text, bounds: word.range, offsetFrom: word.range.lowerBound, by: offset),
                  let pieceEnd = index(in: text, bounds: word.range, offsetFrom: pieceStart, by: 1) else {
                return nil
            }
            offset += 1
            return pieceStart..<pieceEnd
        }

        let content: String
        if piece.hasPrefix(metaspaceReplacement) {
            content = String(piece.dropFirst(metaspaceReplacement.count))
        } else {
            content = piece
        }

        guard !content.isEmpty else { return nil }
        guard let pieceStart = index(in: text, bounds: word.range, offsetFrom: word.range.lowerBound, by: offset),
              let pieceEnd = index(in: text, bounds: word.range, offsetFrom: pieceStart, by: content.count) else {
            return nil
        }
        offset += content.count
        return pieceStart..<pieceEnd
    }

    private func index(
        in text: String,
        bounds: Range<String.Index>,
        offsetFrom start: String.Index,
        by offset: Int
    ) -> String.Index? {
        guard offset >= 0 else { return nil }
        var index = start
        var remaining = offset
        while remaining > 0 {
            guard index < bounds.upperBound else { return nil }
            index = text.index(after: index)
            remaining -= 1
        }
        guard index <= bounds.upperBound else { return nil }
        return index
    }

    private func pretokenSpans(in text: String) -> [PretokenSpan] {
        guard !text.isEmpty else { return [] }
        var spans: [PretokenSpan] = []
        var index = text.startIndex
        while index < text.endIndex {
            let scalar = text[index]
            if scalar.isWhitespace {
                index = text.index(after: index)
                continue
            }
            if isPunctuation(scalar) {
                let next = text.index(after: index)
                spans.append(PretokenSpan(text: String(scalar), range: index..<next))
                index = next
                continue
            }
            let start = index
            index = text.index(after: index)
            while index < text.endIndex {
                let nextScalar = text[index]
                if nextScalar.isWhitespace || isPunctuation(nextScalar) { break }
                index = text.index(after: index)
            }
            spans.append(PretokenSpan(text: String(text[start..<index]), range: start..<index))
        }
        return spans
    }

    private func isPunctuation(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy { CharacterSet.punctuationCharacters.contains($0) }
    }

    private func unigramSegment(
        _ text: String,
        scores: [String: Double],
        unknownScore: Double
    ) -> [String] {
        let chars = Array(text)
        let count = chars.count
        guard count > 0 else { return [] }

        var best = Array(repeating: -Double.infinity, count: count + 1)
        var next = Array(repeating: -1, count: count)
        var usesUNK = Array(repeating: false, count: count)
        best[count] = 0

        for start in stride(from: count - 1, through: 0, by: -1) {
            for end in (start + 1)...count {
                let piece = String(chars[start..<end])
                guard let score = scores[piece] else { continue }
                let candidate = score + best[end]
                if candidate > best[start] {
                    best[start] = candidate
                    next[start] = end
                    usesUNK[start] = false
                }
            }

            let unkCandidate = unknownScore + best[start + 1]
            if unkCandidate > best[start] {
                best[start] = unkCandidate
                next[start] = start + 1
                usesUNK[start] = true
            }
        }

        var pieces: [String] = []
        var position = 0
        let unkPiece = reverseVocab[unkTokenId] ?? "<unk>"
        while position < count {
            let end = next[position]
            guard end > position else {
                pieces.append(unkPiece)
                position += 1
                continue
            }
            if usesUNK[position] {
                pieces.append(unkPiece)
            } else {
                pieces.append(String(chars[position..<end]))
            }
            position = end
        }
        return pieces
    }

    private func wordPiece(
        text: String,
        in wordRange: Range<String.Index>,
        prefix: String
    ) -> [(String, Range<String.Index>)] {
        let word = String(text[wordRange])
        var output: [(String, Range<String.Index>)] = []
        var start = 0
        let chars = Array(word)

        while start < chars.count {
            var end = chars.count
            var curSubstr: String?
            var curLength = 0
            while start < end {
                var substr = String(chars[start..<end])
                if start > 0 { substr = prefix + substr }
                let key = normalizedKey(substr)
                if vocab[key] != nil {
                    curSubstr = key
                    curLength = end - start
                    break
                }
                end -= 1
            }
            if curSubstr == nil {
                // HF WordPiece marks the whole word as [UNK] when any part fails to tokenize;
                // dropping it silently would remove tokens (and spans) from the model input.
                return [(reverseVocab[unkTokenId] ?? "[UNK]", wordRange)]
            }
            let pieceStart = text.index(wordRange.lowerBound, offsetBy: start, limitedBy: wordRange.upperBound) ?? wordRange.upperBound
            let pieceEnd = text.index(pieceStart, offsetBy: curLength, limitedBy: wordRange.upperBound) ?? wordRange.upperBound
            output.append((curSubstr!, pieceStart..<pieceEnd))
            start += curLength
        }
        return output
    }

    private func bpe(
        text: String,
        in wordRange: Range<String.Index>,
        merges: [(String, String)]
    ) -> [(String, Range<String.Index>)] {
        let word = String(text[wordRange])
        guard !word.isEmpty else { return [] }
        var symbols = word.map { String($0) }
        var mergeRank: [String: Int] = [:]
        for (index, merge) in merges.enumerated() {
            mergeRank["\(merge.0) \(merge.1)"] = index
        }

        while symbols.count > 1 {
            var bestRank: Int?
            var bestIndex = -1
            for i in 0 ..< symbols.count - 1 {
                let pair = "\(symbols[i]) \(symbols[i + 1])"
                guard let rank = mergeRank[pair] else { continue }
                if bestRank == nil || rank < bestRank! {
                    bestRank = rank
                    bestIndex = i
                }
            }
            guard bestIndex >= 0 else { break }
            symbols[bestIndex] = symbols[bestIndex] + symbols[bestIndex + 1]
            symbols.remove(at: bestIndex + 1)
        }

        if symbols.count == 1 {
            return [(symbols[0], wordRange)]
        }

        var output: [(String, Range<String.Index>)] = []
        var offset = 0
        for symbol in symbols {
            let start = text.index(wordRange.lowerBound, offsetBy: offset, limitedBy: wordRange.upperBound) ?? wordRange.upperBound
            let end = text.index(start, offsetBy: symbol.count, limitedBy: wordRange.upperBound) ?? wordRange.upperBound
            output.append((symbol, start..<end))
            offset += symbol.count
        }
        return output
    }
}
