import AppKit
import AppUIKit
import DetectionCore
import DocumentCore
import RiskScoringCore
import SwiftUI
import UniformTypeIdentifiers

struct DocumentSanitizeContentView: View {
    let fileURL: URL
    let onReplaceSelection: (URL) -> Void

    @EnvironmentObject private var coordinator: AppCoordinator
    @State private var selectedFile: URL
    @State private var analysisResult: DocumentAnalysisResult?
    @State private var sanitizeResult: DocumentSanitizationResult?
    @State private var selectedEntityIDs: Set<UUID> = []
    @State private var statusMessage: String?
    @State private var errorMessage: String?
    @State private var showsFileTooLargeBuyPro = false
    @State private var isAnalyzing = false
    @State private var isSanitizing = false
    @State private var analysisToken = UUID()
    @State private var activeWork: Task<Void, Never>?
    @State private var redactionPlan: PDFRedactionPlan?
    @State private var manualRegions: [PDFRedactionRegion] = []
    @State private var manualRegionsUndoStack: [[PDFRedactionRegion]] = []
    @State private var manualRegionsRedoStack: [[PDFRedactionRegion]] = []
    @State private var isRefreshingPdfPreview = false
    @State private var previewInFlight = false
    @State private var previewToken = UUID()
    @State private var previewWork: Task<Void, Never>?
    @State private var pdfSessionID = UUID()
    @State private var windowResetToken = UUID()

    private var isBusy: Bool { isAnalyzing || isSanitizing || isRefreshingPdfPreview }

    private var showsWorkingOverlay: Bool {
        isBusy
    }

    init(fileURL: URL, onReplaceSelection: @escaping (URL) -> Void) {
        let standardized = fileURL.standardizedFileURL
        self.fileURL = standardized
        self.onReplaceSelection = onReplaceSelection
        _selectedFile = State(initialValue: standardized)
    }

    private enum Layout {
        static let findingsContentWidth: CGFloat = 320
        static let documentPreviewMinWidth: CGFloat = 390
        static let interColumnSpacing: CGFloat = OFSpacing.lg
        static let horizontalInset: CGFloat = OFSpacing.xxl * 2
        static let windowWidth: CGFloat = findingsContentWidth + documentPreviewMinWidth + interColumnSpacing + horizontalInset
        static let footerHeight: CGFloat = 57
        static let emptyStateHeight: CGFloat = 320
        static let awaitingResultHeight: CGFloat = 280
        static let safeResultHeight: CGFloat = 320
        static let findingsResultHeight: CGFloat = 520
        static let pdfPreviewMinHeight: CGFloat = 420
    }

    private enum WindowContentPhase {
        case awaitingResult
        case safeResult
        case findingsResult
    }

    private var windowContentPhase: WindowContentPhase {
        guard let analysisResult else { return .awaitingResult }
        return showsFindingsLayout(for: analysisResult) ? .findingsResult : .safeResult
    }

    private func showsFindingsLayout(for result: DocumentAnalysisResult) -> Bool {
        !result.detection.entities.isEmpty || result.extracted.format == .pdf
    }

    var body: some View {
        documentSanitizeRoot
    }

    @ViewBuilder
    private var documentSanitizeRoot: some View {
        let bodyHeight = preferredWindowHeight()
        let minimumSize = NSSize(
            width: PrepareWindowChrome.windowWidth(contentWidth: Layout.windowWidth),
            height: PrepareWindowChrome.windowHeight(bodyHeight: bodyHeight)
        )
        let showsFindingsFooter = analysisResult.map { shouldShowPinnedFooter(for: $0) } ?? false
        let showsFileTooLargeFooter = showsFileTooLargeBuyPro

        VStack(spacing: 0) {
            documentBodyContent
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .disabled(showsWorkingOverlay)

            if showsFileTooLargeFooter {
                fileTooLargeProFooter
            } else if showsFindingsFooter, let analysisResult {
                pinnedFooter(for: analysisResult)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .frame(minWidth: Layout.windowWidth, minHeight: bodyHeight)
        .background(
            DocumentSanitizeWindowConfigurator(
                minimumSize: minimumSize,
                preferredSize: minimumSize,
                resetToken: windowResetToken
            )
        )
        .overlay {
            if showsWorkingOverlay {
                workingOverlay
            }
        }
        .onAppear {
            windowResetToken = UUID()
            if analysisResult == nil, !isAnalyzing, !showsFileTooLargeBuyPro {
                selectFile(selectedFile)
            }
        }
        .onDisappear(perform: releaseDocumentSession)
    }

    private func releaseDocumentSession() {
        activeWork?.cancel()
        activeWork = nil
        previewWork?.cancel()
        previewWork = nil
        previewToken = UUID()
        pdfSessionID = UUID()
        resetPdfRedactionState()
        analysisResult = nil
        sanitizeResult = nil
        selectedEntityIDs = []
        isAnalyzing = false
        isSanitizing = false
    }

    private var documentBodyContent: some View {
        VStack(alignment: .leading, spacing: OFSpacing.lg) {
            if let analysisResult {
                if showsFindingsLayout(for: analysisResult) {
                    findingsAndPreviewLayout(for: analysisResult)
                } else {
                    safeDocumentContent
                }
            } else if !isBusy {
                OFButton(
                    title: "",
                    variant: .outline,
                    icon: "arrow.clockwise",
                    small: true
                ) {
                    analyze(fileURL: selectedFile)
                }
            }
        }
        .padding(.horizontal, OFSpacing.md)
        .padding(.bottom, OFSpacing.md)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var safeDocumentContent: some View {
        VStack(spacing: OFSpacing.md) {
            Spacer(minLength: 0)

            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 40, weight: .semibold))
                .foregroundColor(.ofGreen)

            Text(OffsendStrings.documentSanitizeSafeTitle)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.ofText)
                .multilineTextAlignment(.center)

            Text(OffsendStrings.documentSanitizeSafeSubtitle)
                .font(.system(size: 13))
                .foregroundColor(.ofGreenText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.ofGreenDim.opacity(0.55))
        .cornerRadius(OFRadius.lg)
        .overlay(
            RoundedRectangle(cornerRadius: OFRadius.lg)
                .stroke(Color.ofGreen.opacity(0.45), lineWidth: 1)
        )
    }

    private var fileTooLargeProFooter: some View {
        OFPinnedActionFooter(
            statusText: OffsendStrings.documentSanitizeFileTooLargeProNote,
            buttonTitle: OffsendStrings.directoryCheckBuyPro,
            buttonIcon: "crown.fill",
            buttonDisabled: isBusy
        ) {
            Task { await coordinator.openProCheckout(prefillEmail: nil, source: "document_sanitize_file_size") }
        }
    }

    private var workingOverlay: some View {
        ZStack {
            Color.black.opacity(0.12)
            VStack(spacing: OFSpacing.md) {
                ProgressView()
                    .controlSize(.regular)
                Text(isSanitizing ? OffsendStrings.documentSanitizeSanitizing : OffsendStrings.documentSanitizeAnalyzing)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.ofText)
            }
            .padding(OFSpacing.xl)
            .background(Color.ofBg2)
            .cornerRadius(OFRadius.lg)
            .overlay(
                RoundedRectangle(cornerRadius: OFRadius.lg)
                    .stroke(Color.ofBorder, lineWidth: 1)
            )
        }
    }

    private func findingsAndPreviewLayout(for result: DocumentAnalysisResult) -> some View {
        HStack(alignment: .top, spacing: Layout.interColumnSpacing) {
            ScrollView {
                findingsSection(result)
            }
            .frame(width: Layout.findingsContentWidth, alignment: .leading)

            documentPreviewPanel
                .frame(
                    minWidth: Layout.documentPreviewMinWidth,
                    maxWidth: .infinity,
                    minHeight: Layout.pdfPreviewMinHeight,
                    maxHeight: .infinity,
                    alignment: .top
                )
                .layoutPriority(1)
        }
        .frame(minHeight: Layout.findingsResultHeight, maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private var documentPreviewPanel: some View {
        if let result = analysisResult {
            previewSection(for: result)
        }
    }

    @ViewBuilder
    private func previewSection(for result: DocumentAnalysisResult) -> some View {
        if result.extracted.format == .pdf {
            pdfRedactionPreviewSection(for: result)
        } else {
            maskedPreviewSection
        }
    }

    private func findingsSection(_ result: DocumentAnalysisResult) -> some View {
        VStack(alignment: .leading, spacing: OFSpacing.sm) {
            HStack {
                Text(OffsendStrings.documentSanitizeDetectedEntities.uppercased())
                    .font(.system(size: 10.5, weight: .bold))
                    .kerning(0.8)
                    .foregroundColor(.ofTextMuted)

                Spacer()

                if !result.detection.entities.isEmpty {
                    Button {
                        if allEntitiesSelected(for: result) {
                            selectedEntityIDs.removeAll()
                        } else {
                            selectedEntityIDs = Set(result.detection.entities.map(\.id))
                        }
                        refreshPreview(for: result)
                    } label: {
                        Text(
                            allEntitiesSelected(for: result)
                                ? OffsendStrings.documentSanitizeDeselectAll
                                : OffsendStrings.documentSanitizeSelectAll
                        )
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.ofBlue)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 2)

            if result.detection.entities.isEmpty {
                noDetectedEntitiesCard(for: result)
            } else {
                OFCardGroup {
                    ForEach(Array(groupedEntities(for: result).enumerated()), id: \.element.type) { index, group in
                        if index > 0 { OFCardGroupDivider() }
                        entityGroupRow(group, result: result)
                    }
                }
            }

            if !result.detection.entities.isEmpty, selectedEntityIDs.isEmpty {
                Text(OffsendStrings.documentSanitizeNoEntitiesSelected)
                    .font(.system(size: 11))
                    .foregroundColor(.ofAmberText)
            }

            HStack(spacing: OFSpacing.sm) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(OffsendStrings.documentSanitizeRiskScore)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.ofText)

                    OFRiskMeterBar(
                        risk: uiRisk(for: result.assessment),
                        score: min(result.assessment.score, 100)
                    )

                }

                Spacer(minLength: 0)

                OFButton(
                    title: "",
                    variant: .outline,
                    icon: "arrow.clockwise",
                    small: true
                ) {
                    analyze(fileURL: result.extracted.source.sourceURL ?? selectedFile)
                }
                .disabled(isBusy)
            }
        }
    }

    private var maskedPreviewSection: some View {
        VStack(alignment: .leading, spacing: OFSpacing.sm) {
            Text(OffsendStrings.documentSanitizeMaskedPreview.uppercased())
                .font(.system(size: 10.5, weight: .bold))
                .kerning(0.8)
                .foregroundColor(.ofTextMuted)
                .padding(.horizontal, 2)

            ScrollView(.vertical) {
                Text(previewText)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.ofTextSub)
                    .lineSpacing(5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(10)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color.ofBg2)
            .cornerRadius(OFRadius.md)
            .overlay(
                RoundedRectangle(cornerRadius: OFRadius.md)
                    .stroke(Color.ofBorder, lineWidth: 1)
            )
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var previewText: String {
        sanitizeResult?.masking.maskedText ?? analysisResult?.extracted.plainText ?? ""
    }

    @ViewBuilder
    private func pinnedFooter(for result: DocumentAnalysisResult) -> some View {
        let selectedGroupCount = groupedEntities(for: result).filter { group in
            group.entities.contains { selectedEntityIDs.contains($0.id) }
        }.count
        VStack(spacing: 0) {
            OFDivider()

            HStack(spacing: OFSpacing.md) {
                Text(OffsendStrings.documentSanitizeEntitiesSelected(selectedGroupCount))
                    .font(.system(size: 11))
                    .foregroundColor(.ofTextMuted)
                    .lineLimit(1)

                Spacer(minLength: 0)

                OFButton(
                    title: OffsendStrings.documentSanitizeCopySafeText,
                    variant: .outline,
                    icon: "doc.on.doc",
                    small: true,
                    disabled: isBusy || selectedEntityIDs.isEmpty
                ) {
                    copySafeText(for: result)
                }

                OFButton(
                    title: OffsendStrings.documentSanitizeSaveAs,
                    variant: .primary,
                    icon: "square.and.arrow.down",
                    small: true,
                    disabled: isBusy || (isPdfDocument ? !canExportPdfRedaction : selectedEntityIDs.isEmpty)
                ) {
                    saveDocument(for: result)
                }
            }
            .padding(.horizontal, OFSpacing.md)
            .padding(.vertical, OFSpacing.md)
            .background(Color.ofBg0)
        }
    }

    private func entityGroupRow(_ group: EntityGroup, result: DocumentAnalysisResult) -> some View {
        let ids = Set(group.entities.map(\.id))
        let isSelected = ids.isSubset(of: selectedEntityIDs)

        return OFSelectableFixRow(
            badgeStyle: severityBadgeStyle(for: group.type),
            title: AppLocalization.sensitiveEntityTypeName(group.type, plural: group.entities.count != 1),
            description: OffsendStrings.documentSanitizeEntityGroupSummary(group.entities.count),
            isSelected: isSelected
        ) {
            if isSelected {
                selectedEntityIDs.subtract(ids)
            } else {
                selectedEntityIDs.formUnion(ids)
            }
            refreshPreview(for: result)
        }
    }

    private func preferredWindowHeight() -> CGFloat {
        var height: CGFloat
        switch windowContentPhase {
        case .awaitingResult:
            height = Layout.awaitingResultHeight
        case .safeResult:
            height = Layout.safeResultHeight
        case .findingsResult:
            height = Layout.findingsResultHeight + Layout.footerHeight
        }

        if showsFileTooLargeBuyPro {
            height += Layout.footerHeight
        }

        return height
    }

    private func shouldShowPinnedFooter(for result: DocumentAnalysisResult) -> Bool {
        showsFindingsLayout(for: result)
    }

    private func noDetectedEntitiesCard(for result: DocumentAnalysisResult) -> some View {
        VStack(alignment: .leading, spacing: OFSpacing.sm) {
            Text(OffsendStrings.documentSanitizeSafeTitle)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.ofText)

            Text(
                result.extracted.format == .pdf
                    ? OffsendStrings.documentSanitizeEditRedactionsHint
                    : OffsendStrings.documentSanitizeSafeSubtitle
            )
            .font(.system(size: 11))
            .foregroundColor(.ofTextSub)
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(OFSpacing.md)
        .background(Color.ofBg2)
        .cornerRadius(OFRadius.md)
        .overlay(
            RoundedRectangle(cornerRadius: OFRadius.md)
                .stroke(Color.ofBorder, lineWidth: 1)
        )
    }

    private func groupedEntities(for result: DocumentAnalysisResult) -> [EntityGroup] {
        Dictionary(grouping: result.detection.entities, by: \.type)
            .map { EntityGroup(type: $0.key, entities: $0.value.sorted { $0.range.lowerBound < $1.range.lowerBound }) }
            .sorted { $0.type.rawValue < $1.type.rawValue }
    }

    private func allEntitiesSelected(for result: DocumentAnalysisResult) -> Bool {
        selectedEntityIDs.count == result.detection.entities.count
    }

    private func selectFile(_ fileURL: URL) {
        let standardizedURL = fileURL.standardizedFileURL
        selectedFile = standardizedURL
        analysisResult = nil
        sanitizeResult = nil
        selectedEntityIDs = []
        resetPdfRedactionState()
        statusMessage = nil

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

    private func analyze(fileURL: URL) {
        let standardizedURL = fileURL.standardizedFileURL
        let token = UUID()

        selectedFile = standardizedURL
        analysisResult = nil
        sanitizeResult = nil
        selectedEntityIDs = []
        resetPdfRedactionState()
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
                await MainActor.run {
                    guard analysisToken == token else { return }
                    isAnalyzing = false
                    analysisResult = result
                    selectedEntityIDs = Set(result.detection.entities.map(\.id))
                    refreshPreview(for: result)
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard analysisToken == token else { return }
                    isAnalyzing = false
                    applyDocumentProcessingError(error)
                }
            }
        }
    }

    private func copySafeText(for result: DocumentAnalysisResult) {
        guard !isBusy else { return }
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
                await MainActor.run {
                    isSanitizing = false
                    sanitizeResult = sanitized
                    coordinator.copySanitizedDocument(sanitized)
                    statusMessage = OffsendStrings.documentSanitizeCopiedSafeText
                    clearProcessingError()
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    isSanitizing = false
                    applyDocumentProcessingError(error)
                }
            }
        }
    }

    private func saveSafeText(for result: DocumentAnalysisResult) {
        guard !isBusy else { return }
        let entities = selectedEntities(from: result)
        guard !entities.isEmpty else { return }

        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = sanitizedFileName(for: result.extracted.source.fileName)
        panel.allowedContentTypes = [.plainText]

        guard panel.runModal() == .OK, let destinationURL = panel.url else { return }

        isSanitizing = true
        activeWork?.cancel()
        activeWork = Task {
            do {
                let sanitized = try await coordinator.sanitizeDocument(
                    at: result.extracted.source.sourceURL ?? selectedFile,
                    entities: entities
                )
                try coordinator.exportSanitizedDocument(sanitized, to: destinationURL)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    isSanitizing = false
                    sanitizeResult = sanitized
                    statusMessage = OffsendStrings.documentSanitizeSavedSafeText(destinationURL.lastPathComponent)
                    clearProcessingError()
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    isSanitizing = false
                    applyDocumentProcessingError(error)
                }
            }
        }
    }

    private func selectedEntities(from result: DocumentAnalysisResult) -> [SensitiveEntity] {
        result.detection.entities.filter { selectedEntityIDs.contains($0.id) }
    }

    private func sanitizedFileName(for originalName: String) -> String {
        let base = (originalName as NSString).deletingPathExtension
        let ext = (originalName as NSString).pathExtension
        let suffix = OffsendStrings.documentSanitizeSafeSuffix
        if ext.isEmpty {
            return "\(base)\(suffix).txt"
        }
        return "\(base)\(suffix).\(ext)"
    }

    private func documentErrorMessage(_ error: Error) -> String {
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

    private func clearProcessingError() {
        errorMessage = nil
        showsFileTooLargeBuyPro = false
    }

    private func applyFileTooLargeError(byteCount: Int, maximumByteCount: Int) {
        errorMessage = fileTooLargeMessage(byteCount: byteCount, maximumByteCount: maximumByteCount)
        showsFileTooLargeBuyPro = !coordinator.isProEntitlementActive
    }

    private func applyDocumentProcessingError(_ error: Error) {
        errorMessage = documentErrorMessage(error)
        showsFileTooLargeBuyPro = isFileTooLargeOnFreeTier(error)
    }

    private func isFileTooLargeOnFreeTier(_ error: Error) -> Bool {
        guard !coordinator.isProEntitlementActive,
              let error = error as? DocumentProcessingError,
              case .fileTooLarge = error else {
            return false
        }
        return true
    }

    private func fileTooLargeMessage(byteCount: Int, maximumByteCount: Int) -> String {
        let actual = Self.formattedMegabytes(byteCount)
        let limit = Self.formattedMegabytes(maximumByteCount)
        if coordinator.isProEntitlementActive {
            return OffsendStrings.documentSanitizeErrorFileTooLargePro(actual, limit)
        }
        return OffsendStrings.documentSanitizeErrorFileTooLarge(actual, limit)
    }

    private func fileByteCount(at url: URL) -> Int? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber else {
            return nil
        }
        return size.intValue
    }

    private static func formattedMegabytes(_ bytes: Int) -> String {
        let megabytes = Double(bytes) / (1024 * 1024)
        if megabytes >= 10 {
            return String(format: "%.0f MB", megabytes)
        }
        return String(format: "%.1f MB", megabytes)
    }

    private func uiRisk(for assessment: RiskAssessment) -> OFRiskLevel {
        if assessment.hasCriticalSecret { return .critical }
        switch assessment.level {
        case .low:
            return .none
        case .medium:
            return .medium
        case .high, .critical:
            return .critical
        }
    }

    private func severityBadgeStyle(for type: SensitiveEntityType) -> OFStatusBadgeStyle {
        if type.countsAsCriticalSecret { return .fail }
        if type.isSecret { return .warn }
        return .info
    }

    private static var supportedContentTypes: [UTType] {
        DocumentTextExtractorRegistry.supportedFileExtensions.compactMap { UTType(filenameExtension: $0) }
    }

    nonisolated private func fileURL(from item: NSSecureCoding?) -> URL? {
        if let url = item as? URL {
            return url
        }
        if let data = item as? Data {
            return URL(dataRepresentation: data, relativeTo: nil)
        }
        if let string = item as? String {
            return URL(string: string)
        }
        return nil
    }

}

// MARK: - PDF Redaction

extension DocumentSanitizeContentView {
    var isPdfDocument: Bool {
        analysisResult?.extracted.format == .pdf
    }

    private var hasPdfRedactionSelection: Bool {
        !selectedEntityIDs.isEmpty || !manualRegions.isEmpty
    }

    var canExportPdfRedaction: Bool {
        guard hasPdfRedactionSelection, let plan = redactionPlan else { return false }
        return !plan.isEmpty && plan.unresolvedValues.isEmpty
    }

    func resetPdfRedactionState() {
        redactionPlan = nil
        manualRegions = []
        manualRegionsUndoStack = []
        manualRegionsRedoStack = []
        previewInFlight = false
        isRefreshingPdfPreview = false
    }

    var canUndoManualRegions: Bool {
        !manualRegionsUndoStack.isEmpty
    }

    var canRedoManualRegions: Bool {
        !manualRegionsRedoStack.isEmpty
    }

    func pushManualRegionsUndoSnapshot() {
        manualRegionsUndoStack.append(manualRegions)
        if manualRegionsUndoStack.count > 50 {
            manualRegionsUndoStack.removeFirst()
        }
        manualRegionsRedoStack.removeAll()
    }

    func undoManualRegions(for result: DocumentAnalysisResult) {
        guard let previous = manualRegionsUndoStack.popLast() else { return }
        manualRegionsRedoStack.append(manualRegions)
        manualRegions = previous
        refreshPreview(for: result)
    }

    func redoManualRegions(for result: DocumentAnalysisResult) {
        guard let next = manualRegionsRedoStack.popLast() else { return }
        manualRegionsUndoStack.append(manualRegions)
        manualRegions = next
        refreshPreview(for: result)
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
        refreshPreview(for: result)
    }

    @ViewBuilder
    func pdfRedactionPreviewSection(for result: DocumentAnalysisResult) -> some View {
        VStack(alignment: .leading, spacing: OFSpacing.sm) {
            Text(OffsendStrings.documentSanitizeRedactedPreview.uppercased())
                .font(.system(size: 10.5, weight: .bold))
                .kerning(0.8)
                .foregroundColor(.ofTextMuted)
                .padding(.horizontal, 2)

            if let plan = redactionPlan, !plan.unresolvedValues.isEmpty {
                Text(OffsendStrings.documentSanitizeUnresolvedRedactions(plan.unresolvedValues.count))
                    .font(.system(size: 11))
                    .foregroundColor(.ofAmberText)
                    .padding(.horizontal, 2)
            }

            ZStack {
                if result.extracted.format == .pdf {
                    PDFRedactionEditorView(
                        document: pdfEditorDocument,
                        regions: pdfOverlayBoxes,
                        canUndo: canUndoManualRegions,
                        canRedo: canRedoManualRegions,
                        isToolbarDisabled: isBusy,
                        undoAccessibilityLabel: OffsendStrings.documentSanitizeUndo,
                        redoAccessibilityLabel: OffsendStrings.documentSanitizeRedo,
                        onUndo: { undoManualRegions(for: result) },
                        onRedo: { redoManualRegions(for: result) },
                        onManualRegionAdded: { pageIndex, bounds in
                            addManualRegion(pageIndex: pageIndex, bounds: bounds, for: result)
                        }
                    )
                    .id(pdfSessionID)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .frame(minHeight: Layout.pdfPreviewMinHeight)
                } else {
                    RoundedRectangle(cornerRadius: OFRadius.md)
                        .fill(Color.ofBg2)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .frame(minHeight: Layout.pdfPreviewMinHeight)
                }

                if isRefreshingPdfPreview {
                    ZStack {
                        Color.black.opacity(0.08)
                        VStack(spacing: OFSpacing.sm) {
                            ProgressView()
                                .controlSize(.small)
                            Text(OffsendStrings.documentSanitizeRefreshingPreview)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.ofTextSub)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: OFRadius.md))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var pdfEditorDocument: PDFRedactionDocumentSource {
        .file(selectedFile)
    }

    /// Redaction boxes drawn as a live overlay over the original PDF. Manual
    /// regions come straight from local state for instant feedback; resolved
    /// detected regions come from the (asynchronously rebuilt) plan.
    private var pdfOverlayBoxes: [PDFRedactionOverlayBox] {
        var boxes = manualRegions.map {
            PDFRedactionOverlayBox(pageIndex: $0.pageIndex, bounds: $0.bounds)
        }
        if let regions = redactionPlan?.regions {
            boxes += regions.compactMap { region in
                guard case .detected = region.source else { return nil }
                return PDFRedactionOverlayBox(pageIndex: region.pageIndex, bounds: region.bounds)
            }
        }
        return boxes
    }

    private func readPdfData(from fileURL: URL) async -> Data? {
        guard fileURL.pathExtension.lowercased() == "pdf" else { return nil }

        let accessed = fileURL.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                fileURL.stopAccessingSecurityScopedResource()
            }
        }

        return try? Data(contentsOf: fileURL)
    }

    func refreshPreview(for result: DocumentAnalysisResult) {
        refreshTextSanitizePreview(for: result)
        if result.extracted.format == .pdf {
            refreshPDFRedactionPreview(for: result)
        } else {
            redactionPlan = nil
        }
    }

    func refreshTextSanitizePreview(for result: DocumentAnalysisResult) {
        guard !selectedEntityIDs.isEmpty else {
            sanitizeResult = nil
            return
        }

        let entities = result.detection.entities.filter { selectedEntityIDs.contains($0.id) }
        sanitizeResult = coordinator.previewSanitizedDocument(from: result, entities: entities)
    }

    func refreshPDFRedactionPreview(for result: DocumentAnalysisResult) {
        guard hasPdfRedactionSelection else {
            redactionPlan = nil
            previewInFlight = false
            isRefreshingPdfPreview = false
            return
        }

        let token = UUID()
        previewToken = token
        previewInFlight = true
        scheduleRefreshingIndicator(for: token)

        let selectedIDs = selectedEntityIDs
        let manual = manualRegions
        let analysis = result

        previewWork?.cancel()
        previewWork = Task {
            guard let pdfData = await readPdfData(from: selectedFile) else {
                await MainActor.run {
                    guard previewToken == token else { return }
                    previewInFlight = false
                    isRefreshingPdfPreview = false
                }
                return
            }

            do {
                let plan = try await coordinator.buildPDFRedactionPlan(
                    analysis: analysis,
                    pdfData: pdfData,
                    selectedEntityIDs: selectedIDs,
                    manualRegions: manual
                )
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard previewToken == token else { return }
                    redactionPlan = plan
                    previewInFlight = false
                    isRefreshingPdfPreview = false
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard previewToken == token else { return }
                    previewInFlight = false
                    isRefreshingPdfPreview = false
                    applyDocumentProcessingError(error)
                }
            }
        }
    }

    /// Show the dimming "refreshing" overlay only when a rebuild is genuinely
    /// slow. Fast incremental updates (e.g. adding a manual region, whose box is
    /// already drawn instantly via the overlay) finish before this fires, so the
    /// preview pane no longer flashes on every edit.
    private func scheduleRefreshingIndicator(for token: UUID) {
        Task {
            try? await Task.sleep(nanoseconds: 180_000_000)
            await MainActor.run {
                guard previewToken == token, previewInFlight else { return }
                isRefreshingPdfPreview = true
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

    func saveRedactedPDF(for result: DocumentAnalysisResult) {
        guard !isBusy, canExportPdfRedaction else { return }

        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = sanitizedFileName(for: result.extracted.source.fileName)
        panel.allowedContentTypes = [.pdf]

        guard panel.runModal() == .OK, let destinationURL = panel.url else { return }

        isSanitizing = true
        activeWork?.cancel()
        activeWork = Task {
            guard let pdfData = await readPdfData(from: selectedFile) else { return }

            do {
                let session = PDFRedactionSession(
                    sourceData: pdfData,
                    analysis: result,
                    selectedEntityIDs: selectedEntityIDs,
                    manualRegions: manualRegions
                )
                _ = try await coordinator.exportRedactedPDF(session: session, to: destinationURL)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    isSanitizing = false
                    statusMessage = OffsendStrings.documentSanitizeSavedRedactedPDF(
                        destinationURL.lastPathComponent
                    )
                    clearProcessingError()
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    isSanitizing = false
                    applyDocumentProcessingError(error)
                }
            }
        }
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
}

private struct EntityGroup {
    let type: SensitiveEntityType
    let entities: [SensitiveEntity]
}

private struct DocumentSanitizeWindowConfigurator: NSViewRepresentable {
    let minimumSize: NSSize
    let preferredSize: NSSize
    let resetToken: UUID

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            configureWindow(for: view, context: context)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            configureWindow(for: nsView, context: context)
        }
    }

    private func configureWindow(for view: NSView, context: Context) {
        guard let window = view.window else { return }

        window.setFrameAutosaveName("")
        window.minSize = minimumSize

        if context.coordinator.appliedResetToken != resetToken {
            window.setContentSize(preferredSize, animated: false)
            context.coordinator.appliedResetToken = resetToken
            return
        }

        let current = window.contentRect(forFrameRect: window.frame).size
        guard current.width < minimumSize.width || current.height < minimumSize.height else {
            return
        }

        window.setContentSize(
            NSSize(
                width: max(current.width, minimumSize.width),
                height: max(current.height, minimumSize.height)
            ),
            animated: false
        )
    }

    final class Coordinator {
        var appliedResetToken: UUID?
    }
}

private extension NSWindow {
    func setContentSize(_ size: NSSize, animated: Bool) {
        guard animated else {
            setContentSize(size)
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.allowsImplicitAnimation = true
            setContentSize(size)
        }
    }
}
