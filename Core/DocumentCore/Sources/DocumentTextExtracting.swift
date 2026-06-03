import Foundation

public struct DocumentTextExtractionRequest: Equatable, Sendable {
    public let data: Data
    public let source: DocumentSource
    public let maximumExtractedCharacterCount: Int

    public init(data: Data, source: DocumentSource, maximumExtractedCharacterCount: Int) {
        self.data = data
        self.source = source
        self.maximumExtractedCharacterCount = maximumExtractedCharacterCount
    }
}

public struct DocumentTextExtractionResult: Equatable, Sendable {
    public let format: DocumentFormat
    public let plainText: String
    public let warnings: [DocumentProcessingWarning]

    public init(format: DocumentFormat, plainText: String, warnings: [DocumentProcessingWarning] = []) {
        self.format = format
        self.plainText = plainText
        self.warnings = warnings
    }
}

public protocol DocumentTextExtracting: Sendable {
    var id: String { get }
    var supportedFileExtensions: Set<String> { get }

    func canExtract(source: DocumentSource) -> Bool
    func extract(_ request: DocumentTextExtractionRequest) throws -> DocumentTextExtractionResult
}

public protocol DocumentTextExtractorSelecting: Sendable {
    func extractor(for source: DocumentSource) -> (any DocumentTextExtracting)?
}

public struct DocumentTextExtractorRegistry: DocumentTextExtractorSelecting {
    private static let defaultExtractors: [any DocumentTextExtracting] = [
        PlainTextDocumentExtractor(),
        PDFDocumentExtractor()
    ]

    private let extractors: [any DocumentTextExtracting]

    public init(extractors: [any DocumentTextExtracting]) {
        self.extractors = extractors
    }

    public static let `default` = DocumentTextExtractorRegistry(extractors: defaultExtractors)

    public static var supportedFileExtensions: Set<String> {
        defaultExtractors.reduce(into: Set()) { extensions, extractor in
            extensions.formUnion(extractor.supportedFileExtensions)
        }
    }

    public func extractor(for source: DocumentSource) -> (any DocumentTextExtracting)? {
        extractors.first { $0.canExtract(source: source) }
    }
}

public struct DocumentTextExtractor: Sendable {
    private let registry: DocumentTextExtractorSelecting

    public init(registry: DocumentTextExtractorSelecting = DocumentTextExtractorRegistry.default) {
        self.registry = registry
    }

    public func extract(_ request: DocumentProcessingRequest) throws -> ExtractedDocument {
        try DocumentProcessingRequest.validateFileSize(
            request.data.count,
            maximum: request.options.maximumFileByteCount
        )

        let extractionRequest = DocumentTextExtractionRequest(
            data: request.data,
            source: request.source,
            maximumExtractedCharacterCount: request.options.maximumExtractedCharacterCount
        )

        guard let extractor = registry.extractor(for: request.source) else {
            throw DocumentProcessingError.unsupportedFormat(fileExtension: request.source.fileExtension)
        }

        let extraction = try extractor.extract(extractionRequest)
        let normalized = Self.normalizedText(
            extraction.plainText,
            maximumCharacterCount: request.options.maximumExtractedCharacterCount
        )

        guard !normalized.text.isEmpty else {
            throw DocumentProcessingError.emptyDocument
        }

        var warnings = extraction.warnings
        if normalized.wasTruncated {
            warnings.append(
                .textTruncated(
                    originalCharacterCount: normalized.originalCharacterCount,
                    maximumCharacterCount: request.options.maximumExtractedCharacterCount
                )
            )
        }

        return ExtractedDocument(
            source: request.source,
            format: extraction.format,
            plainText: normalized.text,
            characterCount: normalized.text.count,
            wasTruncated: normalized.wasTruncated,
            extractorID: extractor.id,
            warnings: warnings
        )
    }

    private static func normalizedText(
        _ text: String,
        maximumCharacterCount: Int
    ) -> (text: String, wasTruncated: Bool, originalCharacterCount: Int) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > maximumCharacterCount else {
            return (trimmed, false, trimmed.count)
        }
        let endIndex = trimmed.index(trimmed.startIndex, offsetBy: maximumCharacterCount)
        return (String(trimmed[..<endIndex]), true, trimmed.count)
    }
}
