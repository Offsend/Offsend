import AppKit
import AppUIKit
import DetectionCore
import DocumentCore
import Foundation
import PDFKit
import RiskScoringCore
import UniformTypeIdentifiers

@MainActor
final class DocumentSanitizeViewModel: ObservableObject {
    @Published private(set) var selectedFile: URL
    @Published private(set) var analysisResult: DocumentAnalysisResult?
    @Published private(set) var sanitizeResult: DocumentSanitizationResult?
    @Published private(set) var entityGroups: [DocumentSanitizeEntityGroup] = []
    @Published var selectedEntityIDs: Set<UUID> = []
    @Published private(set) var currentAssessment: RiskAssessment?
    @Published private(set) var statusMessage: String?
    @Published private(set) var errorMessage: String?
    @Published private(set) var showsFileTooLargeBuyPro = false
    @Published private(set) var isAnalyzing = false
    @Published private(set) var isSanitizing = false
    @Published private(set) var redactionPlan: PDFRedactionPlan?
    @Published private(set) var manualRegions: [PDFRedactionRegion] = []
    @Published private(set) var pdfOverlayBoxes: [PDFRedactionOverlayBox] = []
    @Published private(set) var isRefreshingPdfPreview = false
    @Published private(set) var pdfSessionID = UUID()

    private weak var coordinator: AppCoordinator?
    private var analysisToken = UUID()
    private var activeWork: Task<Void, Never>?
    private var manualRegionsUndoStack: [[PDFRedactionRegion]] = []
    private var manualRegionsRedoStack: [[PDFRedactionRegion]] = []
    private var previewInFlight = false
    private var previewToken = UUID()
    private var previewWork: Task<Void, Never>?
    private var textPreviewWork: Task<Void, Never>?
    private var cachedPdfData: (url: URL, data: Data)?
    private var cachedPdfDocument: PDFDocument?
    private var cachedAutoRegions: [PDFRedactionRegion] = []
    private let riskScorer = RiskScoringEngine()

    private enum PreviewTiming {
        static let pdfPlanDebounceNanoseconds: UInt64 = 350_000_000
        static let textPreviewDebounceNanoseconds: UInt64 = 100_000_000
        static let refreshingIndicatorDelayNanoseconds: UInt64 = 180_000_000
    }

    var isBusy: Bool { isAnalyzing || isSanitizing || isRefreshingPdfPreview }

    var isPdfDocument: Bool {
        analysisResult?.extracted.format == .pdf
    }

    var canExportPdfRedaction: Bool {
        guard hasPdfRedactionSelection, let plan = redactionPlan else { return false }
        return !plan.isEmpty && plan.unresolvedValues.isEmpty
    }

    var canUndoManualRegions: Bool {
        !manualRegionsUndoStack.isEmpty
    }

    var canRedoManualRegions: Bool {
        !manualRegionsRedoStack.isEmpty
    }

    var previewText: String {
        sanitizeResult?.masking.maskedText ?? analysisResult?.extracted.plainText ?? ""
    }

    var pdfEditorDocument: PDFRedactionDocumentSource {
        if let cachedPdfDocument {
            return .document(cachedPdfDocument, id: pdfSessionID)
        }
        if let data = cachedPdfData?.data {
            // Parse once and keep the document so recreating the editor
            // (tab switches, layout resets) does not re-parse the PDF.
            if let document = PDFDocument(data: data) {
                cachedPdfDocument = document
                return .document(document, id: pdfSessionID)
            }
            return .memory(data, id: pdfSessionID)
        }
        return .file(selectedFile)
    }

    var windowContentPhase: DocumentSanitizeWindowContentPhase {
        analysisResult == nil ? .awaitingResult : .findingsResult
    }

    init(fileURL: URL) {
        selectedFile = fileURL.standardizedFileURL
    }

    func bind(coordinator: AppCoordinator) {
        self.coordinator = coordinator
    }

    func beginInitialAnalysis() {
        if analysisResult == nil, !isAnalyzing, !showsFileTooLargeBuyPro {
            selectFile(selectedFile)
        }
    }

    /// Starts the initial analysis (if needed) and suspends until it finishes.
    func runInitialAnalysis() async {
        beginInitialAnalysis()
        await activeWork?.value
    }

    func releaseSession() {
        activeWork?.cancel()
        activeWork = nil
        previewWork?.cancel()
        previewWork = nil
        textPreviewWork?.cancel()
        textPreviewWork = nil
        previewToken = UUID()
        pdfSessionID = UUID()
        invalidatePdfDataCache()
        resetPdfRedactionState()
        analysisResult = nil
        sanitizeResult = nil
        entityGroups = []
        selectedEntityIDs = []
        currentAssessment = nil
        isAnalyzing = false
        isSanitizing = false
    }

    func preferredWindowHeight() -> CGFloat {
        var height: CGFloat
        switch windowContentPhase {
        case .awaitingResult:
            height = DocumentSanitizeLayout.awaitingResultHeight
        case .findingsResult:
            height = DocumentSanitizeLayout.findingsResultHeight + DocumentSanitizeLayout.footerHeight
        }

        if showsFileTooLargeBuyPro {
            height += DocumentSanitizeLayout.footerHeight
        }

        height += DocumentSanitizeLayout.contentVerticalSlack
        return height
    }

    func allEntitiesSelected(for result: DocumentAnalysisResult) -> Bool {
        selectedEntityIDs.count == result.detection.entities.count
    }

    func selectedGroupCount(for result: DocumentAnalysisResult) -> Int {
        entityGroups.filter { group in
            group.entities.contains { selectedEntityIDs.contains($0.id) }
        }.count
    }

    func toggleSelectAll(for result: DocumentAnalysisResult) {
        if allEntitiesSelected(for: result) {
            selectedEntityIDs.removeAll()
        } else {
            selectedEntityIDs = Set(result.detection.entities.map(\.id))
        }
        applySelectionChange(for: result)
    }

    func toggleEntityGroup(_ group: DocumentSanitizeEntityGroup, for result: DocumentAnalysisResult) {
        if group.entityIDs.isSubset(of: selectedEntityIDs) {
            selectedEntityIDs.subtract(group.entityIDs)
        } else {
            selectedEntityIDs.formUnion(group.entityIDs)
        }
        applySelectionChange(for: result)
    }

    func isEntityGroupSelected(_ group: DocumentSanitizeEntityGroup) -> Bool {
        group.entityIDs.isSubset(of: selectedEntityIDs)
    }

    func selectFile(_ fileURL: URL) {
        let standardizedURL = fileURL.standardizedFileURL
        selectedFile = standardizedURL
        analysisResult = nil
        sanitizeResult = nil
        entityGroups = []
        selectedEntityIDs = []
        currentAssessment = nil
        invalidatePdfDataCache()
        resetPdfRedactionState()
        statusMessage = nil

        guard let coordinator else { return }

        if let fileSize = fileByteCount(at: standardizedURL),
           fileSize > coordinator.documentMaximumFileByteCount {
            applyFileTooLargeError(
                byteCount: fileSize,
                maximumByteCount: coordinator.documentMaximumFileByteCount
            )
            return
        }

        clearProcessingError()
        analyze(fileURL: standardizedURL)
    }

    func analyze(fileURL: URL) {
        analyze(fileURL: fileURL, preservingPresentation: false)
    }

    func reanalyze(fileURL: URL? = nil) {
        let targetURL = fileURL ?? analysisResult?.extracted.source.sourceURL ?? selectedFile
        analyze(fileURL: targetURL, preservingPresentation: true)
    }

    private func analyze(fileURL: URL, preservingPresentation: Bool) {
        guard let coordinator else { return }

        let standardizedURL = fileURL.standardizedFileURL
        let token = UUID()
        let isSameDocumentRefresh = preservingPresentation
            && standardizedURL == selectedFile.standardizedFileURL
            && analysisResult != nil

        selectedFile = standardizedURL

        if isSameDocumentRefresh {
            sanitizeResult = nil
        } else {
            analysisResult = nil
            sanitizeResult = nil
            entityGroups = []
            selectedEntityIDs = []
            currentAssessment = nil
            invalidatePdfDataCache()
            resetPdfRedactionState()
        }

        clearProcessingError()
        statusMessage = nil
        analysisToken = token
        isSanitizing = false
        isAnalyzing = true
        activeWork?.cancel()

        activeWork = Task {
            do {
                let result = try await coordinator.analyzeDocument(at: standardizedURL)
                guard !Task.isCancelled else { return }
                guard analysisToken == token else { return }
                isAnalyzing = false
                applyAnalysisResult(result)
                refreshPreview(for: result)
            } catch {
                guard !Task.isCancelled else { return }
                guard analysisToken == token else { return }
                isAnalyzing = false
                applyDocumentProcessingError(error)
            }
        }
    }

    func copySafeText(for result: DocumentAnalysisResult) {
        guard let coordinator, !isBusy else { return }
        let entities = selectedEntities(from: result)
        guard !entities.isEmpty else { return }

        isSanitizing = true
        activeWork?.cancel()
        activeWork = Task {
            do {
                let sanitized = try await coordinator.sanitizeDocument(
                    at: result.extracted.source.sourceURL ?? selectedFile,
                    entities: entities
                )
                guard !Task.isCancelled else { return }
                isSanitizing = false
                sanitizeResult = sanitized
                coordinator.copySanitizedDocument(sanitized)
                statusMessage = OffsendStrings.documentSanitizeCopiedSafeText
                clearProcessingError()
            } catch {
                guard !Task.isCancelled else { return }
                isSanitizing = false
                applyDocumentProcessingError(error)
            }
        }
    }

    func saveDocument(for result: DocumentAnalysisResult) {
        if result.extracted.format == .pdf {
            saveRedactedPDF(for: result)
        } else {
            saveSafeText(for: result)
        }
    }

    func canSaveDocument(for result: DocumentAnalysisResult) -> Bool {
        guard !isBusy else { return false }
        if result.extracted.format == .pdf {
            return canExportPdfRedaction
        }
        return !selectedEntityIDs.isEmpty
    }

    func saveDocument(for result: DocumentAnalysisResult, to directoryURL: URL) async throws {
        guard canSaveDocument(for: result) else { return }

        let destinationURL = Self.uniqueFileURL(
            in: directoryURL,
            fileName: preparedExportFileName(for: result)
        )

        isSanitizing = true
        defer { isSanitizing = false }

        if result.extracted.format == .pdf {
            try await exportRedactedPDF(for: result, to: destinationURL)
        } else {
            try await exportSafeText(for: result, to: destinationURL)
        }
    }

    func reportSavedAllPrepared(count: Int, folderName: String) {
        statusMessage = OffsendStrings.documentSanitizeSavedAllPrepared(count, folderName)
        clearProcessingError()
    }

    func reportProcessingError(_ error: Error) {
        applyDocumentProcessingError(error)
    }

    func undoManualRegions(for result: DocumentAnalysisResult) {
        guard let previous = manualRegionsUndoStack.popLast() else { return }
        manualRegionsRedoStack.append(manualRegions)
        manualRegions = previous
        rebuildPdfOverlayBoxes()
        applyPdfRedactionSelectionChange(for: result)
    }

    func redoManualRegions(for result: DocumentAnalysisResult) {
        guard let next = manualRegionsRedoStack.popLast() else { return }
        manualRegionsUndoStack.append(manualRegions)
        manualRegions = next
        rebuildPdfOverlayBoxes()
        applyPdfRedactionSelectionChange(for: result)
    }

    func addManualRegion(
        pageIndex: Int,
        bounds: CGRect,
        for result: DocumentAnalysisResult
    ) {
        pushManualRegionsUndoSnapshot()
        manualRegions.append(
            PDFRedactionRegion(
                pageIndex: pageIndex,
                bounds: bounds,
                source: .manual
            )
        )
        rebuildPdfOverlayBoxes()
        applyPdfRedactionSelectionChange(for: result)
    }
}

// MARK: - Private helpers

private extension DocumentSanitizeViewModel {
    var hasPdfRedactionSelection: Bool {
        !selectedEntityIDs.isEmpty || !manualRegions.isEmpty
    }

    func applyAnalysisResult(_ result: DocumentAnalysisResult) {
        analysisResult = result
        entityGroups = DocumentSanitizeEntityGrouping.groups(for: result)
        selectedEntityIDs = Set(result.detection.entities.map(\.id))
        updateCurrentAssessment(for: result)
        cachePdfDataIfNeeded(from: result)
    }

    func resetPdfRedactionState() {
        cachedAutoRegions = []
        redactionPlan = nil
        manualRegions = []
        manualRegionsUndoStack = []
        manualRegionsRedoStack = []
        previewInFlight = false
        isRefreshingPdfPreview = false
        pdfOverlayBoxes = []
    }

    func rebuildPdfOverlayBoxes() {
        var boxes = manualRegions.map {
            PDFRedactionOverlayBox(pageIndex: $0.pageIndex, bounds: $0.bounds)
        }
        if let regions = redactionPlan?.regions {
            boxes += regions.compactMap { region in
                guard case .detected = region.source else { return nil }
                return PDFRedactionOverlayBox(pageIndex: region.pageIndex, bounds: region.bounds)
            }
        }
        pdfOverlayBoxes = boxes
    }

    func invalidatePdfDataCache() {
        cachedPdfData = nil
        cachedPdfDocument = nil
    }

    func pdfData(for fileURL: URL) async -> Data? {
        let standardizedURL = fileURL.standardizedFileURL
        if cachedPdfData?.url == standardizedURL {
            return cachedPdfData?.data
        }

        if let extracted = analysisResult?.extracted,
           extracted.format == .pdf,
           let pdfData = extracted.pdfData {
            cachedPdfData = (standardizedURL, pdfData)
            return pdfData
        }

        guard let data = await loadPdfDataFromDisk(from: standardizedURL) else { return nil }
        cachedPdfData = (standardizedURL, data)
        return data
    }

    func cachePdfDataIfNeeded(from result: DocumentAnalysisResult) {
        guard result.extracted.format == .pdf,
              let pdfData = result.extracted.pdfData else {
            return
        }

        let standardizedURL = selectedFile.standardizedFileURL
        cachedPdfData = (standardizedURL, pdfData)
    }

    func pushManualRegionsUndoSnapshot() {
        manualRegionsUndoStack.append(manualRegions)
        if manualRegionsUndoStack.count > 50 {
            manualRegionsUndoStack.removeFirst()
        }
        manualRegionsRedoStack.removeAll()
    }

    func selectedEntities(from result: DocumentAnalysisResult) -> [SensitiveEntity] {
        result.detection.entities.filter { selectedEntityIDs.contains($0.id) }
    }

    func exportSafeText(for result: DocumentAnalysisResult, to destinationURL: URL) async throws {
        guard let coordinator else { return }
        let sanitized = try await coordinator.sanitizeDocument(
            at: result.extracted.source.sourceURL ?? selectedFile,
            entities: selectedEntities(from: result)
        )
        try coordinator.exportSanitizedDocument(sanitized, to: destinationURL)
        sanitizeResult = sanitized
    }

    func exportRedactedPDF(for result: DocumentAnalysisResult, to destinationURL: URL) async throws {
        guard let coordinator else { return }
        guard let pdfData = await pdfData(for: selectedFile) else { return }

        let session = PDFRedactionSession(
            sourceData: pdfData,
            analysis: result,
            selectedEntityIDs: selectedEntityIDs,
            manualRegions: manualRegions
        )
        _ = try await coordinator.exportRedactedPDF(session: session, to: destinationURL)
    }

    func preparedExportFileName(for result: DocumentAnalysisResult) -> String {
        if result.extracted.format == .pdf {
            return sanitizedRedactedPDFName(for: result.extracted.source.fileName)
        }
        return sanitizedFileName(for: result.extracted.source.fileName)
    }

    static func uniqueFileURL(in directoryURL: URL, fileName: String) -> URL {
        let fileManager = FileManager.default
        var candidate = directoryURL.appendingPathComponent(fileName)
        guard fileManager.fileExists(atPath: candidate.path) else { return candidate }

        let baseName = (fileName as NSString).deletingPathExtension
        let pathExtension = (fileName as NSString).pathExtension

        for suffix in 1...999 {
            let numberedName: String
            if pathExtension.isEmpty {
                numberedName = "\(baseName)-\(suffix)"
            } else {
                numberedName = "\(baseName)-\(suffix).\(pathExtension)"
            }
            candidate = directoryURL.appendingPathComponent(numberedName)
            if !fileManager.fileExists(atPath: candidate.path) {
                return candidate
            }
        }

        return directoryURL.appendingPathComponent(fileName)
    }

    func saveSafeText(for result: DocumentAnalysisResult) {
        guard canSaveDocument(for: result) else { return }

        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = sanitizedFileName(for: result.extracted.source.fileName)
        panel.allowedContentTypes = [.plainText]

        guard panel.runModal() == .OK, let destinationURL = panel.url else { return }

        isSanitizing = true
        activeWork?.cancel()
        activeWork = Task {
            do {
                try await exportSafeText(for: result, to: destinationURL)
                guard !Task.isCancelled else { return }
                isSanitizing = false
                statusMessage = OffsendStrings.documentSanitizeSavedSafeText(destinationURL.lastPathComponent)
                clearProcessingError()
            } catch {
                guard !Task.isCancelled else { return }
                isSanitizing = false
                applyDocumentProcessingError(error)
            }
        }
    }

    func saveRedactedPDF(for result: DocumentAnalysisResult) {
        guard canSaveDocument(for: result) else { return }

        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = sanitizedRedactedPDFName(for: result.extracted.source.fileName)
        panel.allowedContentTypes = [.pdf]

        guard panel.runModal() == .OK, let destinationURL = panel.url else { return }

        isSanitizing = true
        activeWork?.cancel()
        activeWork = Task {
            do {
                try await exportRedactedPDF(for: result, to: destinationURL)
                guard !Task.isCancelled else { return }
                isSanitizing = false
                statusMessage = OffsendStrings.documentSanitizeSavedRedactedPDF(
                    destinationURL.lastPathComponent
                )
                clearProcessingError()
            } catch {
                guard !Task.isCancelled else { return }
                isSanitizing = false
                applyDocumentProcessingError(error)
            }
        }
    }

    func applySelectionChange(for result: DocumentAnalysisResult) {
        updateCurrentAssessment(for: result)
        refreshTextSanitizePreview(for: result)
        applyPdfRedactionSelectionChange(for: result)
    }

    func refreshPreview(for result: DocumentAnalysisResult) {
        refreshTextSanitizePreview(for: result)
        if result.extracted.format == .pdf {
            refreshPDFRedactionPreview(for: result)
        } else {
            redactionPlan = nil
        }
    }

    func updateCurrentAssessment(for result: DocumentAnalysisResult) {
        let exposedEntities = result.detection.entities.filter { !selectedEntityIDs.contains($0.id) }
        currentAssessment = riskScorer.assess(exposedEntities)
    }

    func applyPdfRedactionSelectionChange(for result: DocumentAnalysisResult) {
        guard result.extracted.format == .pdf else { return }

        guard hasPdfRedactionSelection else {
            previewWork?.cancel()
            redactionPlan = nil
            previewInFlight = false
            isRefreshingPdfPreview = false
            rebuildPdfOverlayBoxes()
            return
        }

        if applyCachedPdfRedactionPlan(for: result) {
            return
        }

        refreshPDFRedactionPreview(for: result)
    }

    func applyCachedPdfRedactionPlan(for result: DocumentAnalysisResult) -> Bool {
        guard !cachedAutoRegions.isEmpty || !manualRegions.isEmpty else { return false }

        redactionPlan = PDFRedactionPlanBuilder.composePlan(
            selectedEntityIDs: selectedEntityIDs,
            manualRegions: manualRegions,
            resolvedAutoRegions: cachedAutoRegions,
            selectedEntities: selectedEntities(from: result)
        )
        rebuildPdfOverlayBoxes()
        return true
    }

    func detectedAutoRegions(from plan: PDFRedactionPlan) -> [PDFRedactionRegion] {
        plan.regions.filter { region in
            if case .detected = region.source { return true }
            return false
        }
    }

    func refreshTextSanitizePreview(for result: DocumentAnalysisResult) {
        guard !selectedEntityIDs.isEmpty else {
            textPreviewWork?.cancel()
            sanitizeResult = nil
            return
        }

        let token = analysisToken
        textPreviewWork?.cancel()
        textPreviewWork = Task {
            try? await Task.sleep(nanoseconds: PreviewTiming.textPreviewDebounceNanoseconds)
            guard !Task.isCancelled else { return }
            guard let coordinator else { return }
            guard !selectedEntityIDs.isEmpty else {
                sanitizeResult = nil
                return
            }

            let entities = result.detection.entities.filter { selectedEntityIDs.contains($0.id) }
            let preview = await coordinator.previewSanitizedDocument(from: result, entities: entities)
            guard !Task.isCancelled, analysisToken == token else { return }
            sanitizeResult = preview
        }
    }

    func refreshPDFRedactionPreview(for result: DocumentAnalysisResult) {
        guard let coordinator else { return }

        guard hasPdfRedactionSelection else {
            previewWork?.cancel()
            redactionPlan = nil
            previewInFlight = false
            isRefreshingPdfPreview = false
            rebuildPdfOverlayBoxes()
            return
        }

        let token = UUID()
        previewToken = token

        previewWork?.cancel()
        previewWork = Task {
            try? await Task.sleep(nanoseconds: PreviewTiming.pdfPlanDebounceNanoseconds)
            guard !Task.isCancelled else { return }
            guard previewToken == token else { return }
            guard hasPdfRedactionSelection else {
                previewInFlight = false
                isRefreshingPdfPreview = false
                return
            }

            previewInFlight = true
            scheduleRefreshingIndicator(for: token)

            let analysis = result

            guard let pdfData = await pdfData(for: selectedFile) else {
                guard previewToken == token else { return }
                previewInFlight = false
                isRefreshingPdfPreview = false
                return
            }

            do {
                if cachedAutoRegions.isEmpty, !analysis.detection.entities.isEmpty {
                    let allEntityIDs = Set(analysis.detection.entities.map(\.id))
                    let fullPlan = try await coordinator.buildPDFRedactionPlan(
                        analysis: analysis,
                        pdfData: pdfData,
                        selectedEntityIDs: allEntityIDs,
                        manualRegions: []
                    )
                    guard !Task.isCancelled else { return }
                    guard previewToken == token else { return }
                    cachedAutoRegions = detectedAutoRegions(from: fullPlan)
                }

                guard !Task.isCancelled else { return }
                guard previewToken == token else { return }
                _ = applyCachedPdfRedactionPlan(for: analysis)
                previewInFlight = false
                isRefreshingPdfPreview = false
            } catch {
                guard !Task.isCancelled else { return }
                guard previewToken == token else { return }
                previewInFlight = false
                isRefreshingPdfPreview = false
                applyDocumentProcessingError(error)
            }
        }
    }

    func scheduleRefreshingIndicator(for token: UUID) {
        Task {
            try? await Task.sleep(nanoseconds: PreviewTiming.refreshingIndicatorDelayNanoseconds)
            guard previewToken == token, previewInFlight else { return }
            isRefreshingPdfPreview = true
        }
    }

    func loadPdfDataFromDisk(from fileURL: URL) async -> Data? {
        guard fileURL.pathExtension.lowercased() == "pdf" else { return nil }

        let accessed = fileURL.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                fileURL.stopAccessingSecurityScopedResource()
            }
        }

        return try? Data(contentsOf: fileURL)
    }

    func sanitizedFileName(for originalName: String) -> String {
        let base = (originalName as NSString).deletingPathExtension
        let ext = (originalName as NSString).pathExtension
        let suffix = OffsendStrings.documentSanitizeSafeSuffix
        if ext.isEmpty {
            return "\(base)\(suffix).txt"
        }
        return "\(base)\(suffix).\(ext)"
    }

    func sanitizedRedactedPDFName(for originalName: String) -> String {
        let base = (originalName as NSString).deletingPathExtension
        let suffix = OffsendStrings.documentSanitizeSafeSuffix
        return "\(base)\(suffix).pdf"
    }

    func documentErrorMessage(_ error: Error) -> String {
        if let error = error as? PDFRedactionError {
            return pdfRedactionErrorMessage(error)
        }
        if let error = error as? DocumentProcessingError {
            switch error {
            case let .unsupportedFormat(fileExtension):
                return OffsendStrings.documentSanitizeErrorUnsupportedFormat(fileExtension)
            case let .fileTooLarge(byteCount, maximumByteCount):
                return fileTooLargeMessage(byteCount: byteCount, maximumByteCount: maximumByteCount)
            case .emptyDocument:
                return OffsendStrings.documentSanitizeErrorEmptyDocument
            case .invalidPDF:
                return OffsendStrings.documentSanitizeErrorInvalidPDF
            case let .unreadableFile(message):
                return OffsendStrings.documentSanitizeErrorUnreadableFile(message)
            case let .extractionFailed(message):
                return OffsendStrings.documentSanitizeErrorExtractionFailed(message)
            }
        }
        return error.localizedDescription
    }

    func pdfRedactionErrorMessage(_ error: PDFRedactionError) -> String {
        switch error {
        case .invalidPDF:
            return OffsendStrings.documentSanitizeErrorInvalidPDF
        case .encryptedPDF:
            return OffsendStrings.documentSanitizeErrorInvalidPDF
        case .noTextLayer:
            return OffsendStrings.documentSanitizeErrorEmptyDocument
        case .unsupportedFormat:
            return OffsendStrings.documentSanitizeErrorUnsupportedFormat("pdf")
        case .emptyPlan:
            return OffsendStrings.documentSanitizeNoEntitiesSelected
        case let .unresolvedValues(values):
            return OffsendStrings.documentSanitizeErrorUnresolvedRedactions(values.count)
        case let .exportFailed(message):
            return OffsendStrings.documentSanitizeErrorExtractionFailed(message)
        }
    }

    func clearProcessingError() {
        errorMessage = nil
        showsFileTooLargeBuyPro = false
    }

    func applyFileTooLargeError(byteCount: Int, maximumByteCount: Int) {
        errorMessage = fileTooLargeMessage(byteCount: byteCount, maximumByteCount: maximumByteCount)
        showsFileTooLargeBuyPro = !(coordinator?.isProEntitlementActive ?? false)
    }

    func applyDocumentProcessingError(_ error: Error) {
        errorMessage = documentErrorMessage(error)
        showsFileTooLargeBuyPro = isFileTooLargeOnFreeTier(error)
    }

    func isFileTooLargeOnFreeTier(_ error: Error) -> Bool {
        guard coordinator?.isProEntitlementActive == false,
              let error = error as? DocumentProcessingError,
              case .fileTooLarge = error else {
            return false
        }
        return true
    }

    func fileTooLargeMessage(byteCount: Int, maximumByteCount: Int) -> String {
        let actual = Self.formattedMegabytes(byteCount)
        let limit = Self.formattedMegabytes(maximumByteCount)
        if coordinator?.isProEntitlementActive == true {
            return OffsendStrings.documentSanitizeErrorFileTooLargePro(actual, limit)
        }
        return OffsendStrings.documentSanitizeErrorFileTooLarge(actual, limit)
    }

    func fileByteCount(at url: URL) -> Int? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber else {
            return nil
        }
        return size.intValue
    }

    static func formattedMegabytes(_ bytes: Int) -> String {
        let megabytes = Double(bytes) / (1024 * 1024)
        if megabytes >= 10 {
            return String(format: "%.0f MB", megabytes)
        }
        return String(format: "%.1f MB", megabytes)
    }
}
