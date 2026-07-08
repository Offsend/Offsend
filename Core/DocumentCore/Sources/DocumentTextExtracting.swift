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
    public let pdfData: Data?

    public init(
        format: DocumentFormat,
        plainText: String,
        warnings: [DocumentProcessingWarning] = [],
        pdfData: Data? = nil
    ) {
        self.format = format
        self.plainText = plainText
        self.warnings = warnings
        self.pdfData = pdfData
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
    private let extractors: [any DocumentTextExtracting]

    public init(extractors: [any DocumentTextExtracting]) {
        self.extractors = extractors
    }

    /// Full registry for the macOS app: RTF, Word, PDF (when available), and plain text.
    public static var `default`: DocumentTextExtractorRegistry {
        DocumentTextExtractorRegistry(extractors: builtInExtractors())
    }

    /// Plain-text-only registry for cross-platform CLI and CI.
    public static let cliDefault = DocumentTextExtractorRegistry(extractors: [
        PlainTextDocumentExtractor()
    ])

    public static var supportedFileExtensions: Set<String> {
        builtInExtractors().reduce(into: Set()) { extensions, extractor in
            extensions.formUnion(extractor.supportedFileExtensions)
        }
    }

    public static func canProcess(source: DocumentSource) -> Bool {
        `default`.extractor(for: source) != nil
    }

    public static func canProcessFile(at url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              !isDirectory.boolValue else {
            return false
        }

        let source = DocumentSource(fileName: url.lastPathComponent, sourceURL: url)
        return canProcess(source: source)
    }

    public func extractor(for source: DocumentSource) -> (any DocumentTextExtracting)? {
        extractors.first { $0.canExtract(source: source) }
    }

    private static func builtInExtractors() -> [any DocumentTextExtracting] {
        var extractors: [any DocumentTextExtracting] = []
        #if canImport(AppKit)
        extractors.append(RTFDocumentExtractor())
        extractors.append(WordDocumentExtractor())
        #endif
        #if canImport(PDFKit)
        extractors.append(PDFDocumentExtractor())
        #endif
        extractors.append(PlainTextDocumentExtractor())
        return extractors
    }
}

public struct DocumentTextExtractor: Sendable {
    private let registry: DocumentTextExtractorSelecting

    public init(registry: DocumentTextExtractorSelecting = DocumentTextExtractorRegistry.default) {
        self.registry = registry
    }

    public static func forCLI() -> DocumentTextExtractor {
        DocumentTextExtractor(registry: DocumentTextExtractorRegistry.cliDefault)
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

        guard !normalized.text.isEmpty || extraction.format == .pdf else {
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
            warnings: warnings,
            pdfData: extraction.pdfData
        )
    }

    private static func normalizedText(
        _ text: String,
        maximumCharacterCount: Int
    ) -> (text: String, wasTruncated: Bool, originalCharacterCount: Int) {
        // Extractors (e.g. PDF) often already return edge-trimmed text; skip the extra
        // full-string copy unless an edge actually carries whitespace.
        let needsTrim = (text.first?.isWhitespace ?? false) || (text.last?.isWhitespace ?? false)
        let trimmed = needsTrim ? text.trimmingCharacters(in: .whitespacesAndNewlines) : text
        guard trimmed.count > maximumCharacterCount else {
            return (trimmed, false, trimmed.count)
        }
        let endIndex = trimmed.index(trimmed.startIndex, offsetBy: maximumCharacterCount)
        return (String(trimmed[..<endIndex]), true, trimmed.count)
    }
}
