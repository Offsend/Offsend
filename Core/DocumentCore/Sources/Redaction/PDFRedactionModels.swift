import CoreGraphics
import DetectionCore
import Foundation

public enum PDFRedactionSource: Equatable, Sendable {
    case detected(entityID: UUID, value: String)
    case manual
}

public struct PDFRedactionRegion: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let pageIndex: Int
    public let bounds: CGRect
    public let source: PDFRedactionSource

    public init(
        id: UUID = UUID(),
        pageIndex: Int,
        bounds: CGRect,
        source: PDFRedactionSource
    ) {
        self.id = id
        self.pageIndex = pageIndex
        self.bounds = bounds
        self.source = source
    }
}

public struct PDFRedactionPlan: Equatable, Sendable {
    public let regions: [PDFRedactionRegion]
    public let unresolvedValues: [String]

    public init(regions: [PDFRedactionRegion], unresolvedValues: [String] = []) {
        self.regions = regions
        self.unresolvedValues = unresolvedValues
    }

    public var isEmpty: Bool { regions.isEmpty }
}

public struct PDFRedactionSession: @unchecked Sendable {
    public let sourceData: Data
    public let analysis: DocumentAnalysisResult
    public var selectedEntityIDs: Set<UUID>
    public var manualRegions: [PDFRedactionRegion]
    /// When `false` (default), export fails if detected values have no PDF layout regions.
    public let allowExportWithUnresolvedValues: Bool

    public init(
        sourceData: Data,
        analysis: DocumentAnalysisResult,
        selectedEntityIDs: Set<UUID>,
        manualRegions: [PDFRedactionRegion] = [],
        allowExportWithUnresolvedValues: Bool = false
    ) {
        self.sourceData = sourceData
        self.analysis = analysis
        self.selectedEntityIDs = selectedEntityIDs
        self.manualRegions = manualRegions
        self.allowExportWithUnresolvedValues = allowExportWithUnresolvedValues
    }
}

public enum PDFRedactionWarning: Equatable, Sendable {
    case valueNotFoundInPDF(String)
}

public struct PDFRedactionResult: Equatable, Sendable {
    public let plan: PDFRedactionPlan
    public let redactedData: Data
    public let warnings: [PDFRedactionWarning]

    public init(plan: PDFRedactionPlan, redactedData: Data, warnings: [PDFRedactionWarning] = []) {
        self.plan = plan
        self.redactedData = redactedData
        self.warnings = warnings
    }
}

public enum PDFRedactionApplyMode: Sendable {
    case preview
    case permanent
}

public enum PDFRedactionError: Error, Equatable {
    case invalidPDF
    case encryptedPDF
    case noTextLayer
    case unsupportedFormat
    case emptyPlan
    case unresolvedValues([String])
    case exportFailed(message: String)
}

public enum PDFRedactionDefaults {
    public static let regionPadding: CGFloat = 1
}
