import DetectionCore
import Foundation
import MaskingCore
import RiskScoringCore

public enum DocumentFormat: String, Codable, CaseIterable, Sendable, Equatable {
    case plainText
    case pdf
}

public struct DocumentSource: Equatable, Sendable {
    public let fileName: String
    public let fileExtension: String
    public let sourceURL: URL?

    public init(fileName: String, sourceURL: URL? = nil) {
        self.fileName = fileName
        self.fileExtension = (fileName as NSString).pathExtension.lowercased()
        self.sourceURL = sourceURL
    }
}

public enum DocumentProcessingWarning: Equatable, Sendable {
    case textTruncated(originalCharacterCount: Int, maximumCharacterCount: Int)
}

public enum DocumentProcessingError: Error, Equatable {
    case unsupportedFormat(fileExtension: String)
    case fileTooLarge(byteCount: Int, maximumByteCount: Int)
    case emptyDocument
    case invalidPDF
    case unreadableFile(message: String)
    case extractionFailed(message: String)
}

public struct DocumentProcessingOptions: Equatable, Sendable {
    public var detection: DetectionOptions
    public var mappingTTL: MappingTTL
    public var maximumFileByteCount: Int
    public var maximumExtractedCharacterCount: Int

    public init(
        detection: DetectionOptions = .default,
        mappingTTL: MappingTTL = .oneHour,
        maximumFileByteCount: Int = DocumentProcessingLimits.freeMaximumFileByteCount,
        maximumExtractedCharacterCount: Int = 500_000
    ) {
        self.detection = detection
        self.mappingTTL = mappingTTL
        self.maximumFileByteCount = maximumFileByteCount
        self.maximumExtractedCharacterCount = maximumExtractedCharacterCount
    }

    public static let `default` = DocumentProcessingOptions()
}

public struct DocumentProcessingRequest: Equatable, Sendable {
    public let data: Data
    public let source: DocumentSource
    public let options: DocumentProcessingOptions

    public init(
        data: Data,
        source: DocumentSource,
        options: DocumentProcessingOptions = .default
    ) {
        self.data = data
        self.source = source
        self.options = options
    }

    public init(
        fileURL: URL,
        reader: DocumentReading = FileManagerDocumentReader(),
        options: DocumentProcessingOptions = .default
    ) throws {
        let data = try reader.data(at: fileURL)
        try Self.validateFileSize(data.count, maximum: options.maximumFileByteCount)
        self.init(
            data: data,
            source: DocumentSource(fileName: fileURL.lastPathComponent, sourceURL: fileURL),
            options: options
        )
    }

    public static func validateFileSize(_ byteCount: Int, maximum: Int) throws {
        guard byteCount <= maximum else {
            throw DocumentProcessingError.fileTooLarge(byteCount: byteCount, maximumByteCount: maximum)
        }
    }
}

public struct ExtractedDocument: Equatable, Sendable {
    public let source: DocumentSource
    public let format: DocumentFormat
    public let plainText: String
    public let characterCount: Int
    public let wasTruncated: Bool
    public let extractorID: String
    public let warnings: [DocumentProcessingWarning]
    /// PDF bytes used for redaction preview and export. Populated for native PDF and Word documents.
    public let pdfData: Data?

    public init(
        source: DocumentSource,
        format: DocumentFormat,
        plainText: String,
        characterCount: Int,
        wasTruncated: Bool,
        extractorID: String,
        warnings: [DocumentProcessingWarning] = [],
        pdfData: Data? = nil
    ) {
        self.source = source
        self.format = format
        self.plainText = plainText
        self.characterCount = characterCount
        self.wasTruncated = wasTruncated
        self.extractorID = extractorID
        self.warnings = warnings
        self.pdfData = pdfData
    }
}

public struct DocumentAnalysisResult {
    public let extracted: ExtractedDocument
    public let detection: DetectionResult
    public let assessment: RiskAssessment

    public init(
        extracted: ExtractedDocument,
        detection: DetectionResult,
        assessment: RiskAssessment
    ) {
        self.extracted = extracted
        self.detection = detection
        self.assessment = assessment
    }
}

public struct DocumentSanitizationResult {
    public let extracted: ExtractedDocument
    public let detection: DetectionResult
    public let assessment: RiskAssessment
    public let masking: MaskingResult

    public init(
        extracted: ExtractedDocument,
        detection: DetectionResult,
        assessment: RiskAssessment,
        masking: MaskingResult
    ) {
        self.extracted = extracted
        self.detection = detection
        self.assessment = assessment
        self.masking = masking
    }
}
