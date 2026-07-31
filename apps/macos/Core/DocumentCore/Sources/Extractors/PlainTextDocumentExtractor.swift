import Foundation

public struct PlainTextDocumentExtractor: DocumentTextExtracting {
    public static let supportedExtensions: Set<String> = [
        "txt", "md", "markdown", "csv", "json", "log", "xml", "yaml", "yml"
    ]

    /// Extensions handled by dedicated extractors; plain text acts as fallback for everything else.
    static let reservedExtensions: Set<String> = ["pdf", "doc", "docx", "rtf"]

    public let id = "plain-text"
    public let supportedFileExtensions: Set<String>

    public init(supportedFileExtensions: Set<String> = PlainTextDocumentExtractor.supportedExtensions) {
        self.supportedFileExtensions = supportedFileExtensions
    }

    public func canExtract(source: DocumentSource) -> Bool {
        if supportedFileExtensions.contains(source.fileExtension) {
            return true
        }
        guard !Self.reservedExtensions.contains(source.fileExtension) else {
            return false
        }
        if let url = source.sourceURL,
           let data = try? Data(contentsOf: url, options: [.mappedIfSafe]) {
            return TextFileDetection.isLikelyText(data: data)
        }
        return true
    }

    public func extract(_ request: DocumentTextExtractionRequest) throws -> DocumentTextExtractionResult {
        let text = Self.decodeText(from: request.data)
        return DocumentTextExtractionResult(format: .plainText, plainText: text)
    }

    private static func decodeText(from data: Data) -> String {
        if let utf8 = String(data: data, encoding: .utf8) {
            return utf8
        }
        // ISO Latin-1 maps every byte value, so this never fails for non-empty data.
        return String(data: data, encoding: .isoLatin1) ?? ""
    }
}

enum TextFileDetection {
    static func isLikelyText(data: Data) -> Bool {
        guard !data.isEmpty else { return true }

        let sample = data.prefix(8192)
        if sample.contains(0) {
            return false
        }
        if String(data: sample, encoding: .utf8) != nil {
            return true
        }

        let printableCount = sample.reduce(into: 0) { count, byte in
            if byte == 0x09 || byte == 0x0A || byte == 0x0D {
                count += 1
            } else if (0x20 ... 0x7E).contains(byte) || byte >= 0xA0 {
                count += 1
            }
        }
        return Double(printableCount) / Double(sample.count) >= 0.85
    }
}
