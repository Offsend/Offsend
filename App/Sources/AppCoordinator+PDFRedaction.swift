import DocumentCore
import Foundation

extension AppCoordinator {
    func buildPDFRedactionPlan(
        analysis: DocumentAnalysisResult,
        pdfData: Data,
        selectedEntityIDs: Set<UUID>,
        manualRegions: [PDFRedactionRegion] = []
    ) async throws -> PDFRedactionPlan {
        try await Task.detached {
            try PDFRedactionPlanBuilder().buildPlan(
                analysis: analysis,
                pdfData: pdfData,
                selectedEntityIDs: selectedEntityIDs,
                manualRegions: manualRegions
            )
        }.value
    }

    func exportRedactedPDF(
        session: PDFRedactionSession,
        to destinationURL: URL
    ) async throws -> PDFRedactionResult {
        let result = try await Task.detached {
            try PDFRedactionExporter().export(session: session, to: destinationURL)
        }.value
        analytics.track(.maskApplied)
        return result
    }
}
