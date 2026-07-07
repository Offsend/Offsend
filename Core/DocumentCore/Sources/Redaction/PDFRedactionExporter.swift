import Foundation

public protocol PDFRedactionExporting: Sendable {
    func export(session: PDFRedactionSession, to destinationURL: URL) throws -> PDFRedactionResult
}

#if canImport(PDFKit)
public struct PDFRedactionExporter: PDFRedactionExporting {
    private let planBuilder: PDFRedactionPlanBuilding
    private let redactionEngine: PDFRedactionApplying

    public init(
        planBuilder: PDFRedactionPlanBuilding = PDFRedactionPlanBuilder(),
        redactionEngine: PDFRedactionApplying = PDFRedactionEngine()
    ) {
        self.planBuilder = planBuilder
        self.redactionEngine = redactionEngine
    }

    public func export(session: PDFRedactionSession, to destinationURL: URL) throws -> PDFRedactionResult {
        let plan = try planBuilder.buildPlan(
            analysis: session.analysis,
            pdfData: session.sourceData,
            selectedEntityIDs: session.selectedEntityIDs,
            manualRegions: session.manualRegions
        )

        if !plan.unresolvedValues.isEmpty, !session.allowExportWithUnresolvedValues {
            throw PDFRedactionError.unresolvedValues(plan.unresolvedValues)
        }

        guard !plan.isEmpty else {
            throw PDFRedactionError.emptyPlan
        }

        let redactedData = try redactionEngine.apply(
            plan: plan,
            to: session.sourceData,
            mode: .permanent
        )

        try redactedData.write(to: destinationURL, options: .atomic)

        let warnings = plan.unresolvedValues.map(PDFRedactionWarning.valueNotFoundInPDF)
        return PDFRedactionResult(plan: plan, redactedData: redactedData, warnings: warnings)
    }
}
#endif
