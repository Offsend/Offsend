import AppKit
import AppUIKit
import DetectionCore
import DocumentCore
import RiskScoringCore
import SwiftUI
import UniformTypeIdentifiers

struct DocumentSanitizeView: View {
    let documentWindowPath: String?

    @EnvironmentObject private var coordinator: AppCoordinator
    @State private var selectedFile: URL?
    @State private var analysisResult: DocumentAnalysisResult?
    @State private var sanitizeResult: DocumentSanitizationResult?
    @State private var selectedEntityIDs: Set<UUID> = []
    @State private var isDropTargeted = false
    @State private var statusMessage: String?
    @State private var errorMessage: String?
    @State private var showsFileTooLargeBuyPro = false
    @State private var isAnalyzing = false
    @State private var isSanitizing = false
    @State private var analysisToken = UUID()
    @State private var activeWork: Task<Void, Never>?

    private var isBusy: Bool { isAnalyzing || isSanitizing }

    private var isBootstrapPending: Bool {
        documentWindowPath != nil && analysisResult == nil && selectedFile == nil
    }

    private var showsWorkingOverlay: Bool {
        isBusy || isBootstrapPending
    }

    private enum Layout {
        static let windowWidth: CGFloat = 640
        static let headerHeight: CGFloat = 96
        static let footerHeight: CGFloat = 57
        static let bannerExtraHeight: CGFloat = 72
        static let emptyStateHeight: CGFloat = 392
        static let awaitingResultHeight: CGFloat = 372
        static let safeResultHeight: CGFloat = 448
        static let findingsResultHeight: CGFloat = 780
    }

    private enum WindowContentPhase {
        case empty
        case awaitingResult
        case safeResult
        case findingsResult
    }

    private var windowContentPhase: WindowContentPhase {
        guard selectedFile != nil else { return .empty }
        guard let analysisResult else { return .awaitingResult }
        return analysisResult.detection.entities.isEmpty ? .safeResult : .findingsResult
    }

    private var usesScrollableContent: Bool {
        windowContentPhase == .findingsResult
    }

    var body: some View {
        let windowHeight = preferredWindowHeight()
        let windowSize = NSSize(width: Layout.windowWidth, height: windowHeight)
        let showsFindingsFooter = analysisResult.map { shouldShowPinnedFooter(for: $0) } ?? false
        let showsFileTooLargeFooter = showsFileTooLargeBuyPro && selectedFile != nil

        VStack(spacing: 0) {
            header
                .padding(.horizontal, OFSpacing.xxl)
                .padding(.top, OFSpacing.xl)
                .padding(.bottom, OFSpacing.lg)

            Group {
                if usesScrollableContent {
                    ScrollView {
                        documentBodyContent
                    }
                } else {
                    documentBodyContent
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
            }

            if showsFileTooLargeFooter {
                fileTooLargeProFooter
            } else if showsFindingsFooter, let analysisResult {
                pinnedFooter(for: analysisResult)
            }
        }
        .frame(width: Layout.windowWidth, height: windowHeight, alignment: .top)
        .background(Color.ofBg1)
        .background(DocumentSanitizeWindowSizer(size: windowSize))
        .overlay {
            if showsWorkingOverlay {
                workingOverlay
            }
        }
        .disabled(showsWorkingOverlay)
        .onAppear {
            prefillFileFromPasteboard()
            bootstrapFromWindowPathIfNeeded()
        }
        .onChange(of: documentWindowPath) { _ in
            bootstrapFromWindowPathIfNeeded()
        }
        .onDisappear {
            activeWork?.cancel()
            activeWork = nil
        }
        .dismissOnWindowCloseButton()
    }

    private var documentBodyContent: some View {
        VStack(alignment: .leading, spacing: OFSpacing.lg) {
            privacyNote

            if selectedFile == nil {
                emptyDropZone
            } else if let analysisResult {
                fileSummaryCard(analysisResult)

                if let errorMessage {
                    errorBanner(errorMessage)
                }

                if let statusMessage {
                    statusBanner(statusMessage)
                }

                if analysisResult.detection.entities.isEmpty {
                    safeDocumentBanner
                } else {
                    findingsSection(analysisResult)
                    maskedPreviewSection
                }
            } else if let selectedFile {
                selectedFileSummaryCard(selectedFile)

                if let errorMessage {
                    errorBanner(errorMessage)
                }

                if !isBusy {
                    OFButton(
                        title: OffsendStrings.documentSanitizeRefreshAnalysis,
                        variant: .outline,
                        icon: "arrow.clockwise",
                        small: true
                    ) {
                        analyze(fileURL: selectedFile)
                    }
                }
            }
        }
        .padding(.horizontal, OFSpacing.xxl)
        .padding(.bottom, OFSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            OFIconTile(
                systemName: "doc.text.magnifyingglass",
                tint: .ofBlue,
                size: 44,
                iconSize: 18,
                glow: true
            )

            VStack(alignment: .leading, spacing: 3) {
                Text(OffsendStrings.documentSanitizeTitle)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.ofText)

                Text(OffsendStrings.documentSanitizeSubtitle)
                    .font(.system(size: 12))
                    .foregroundColor(.ofTextMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            OFButton(
                title: OffsendStrings.documentSanitizeChooseFile,
                variant: .outline,
                icon: "doc",
                small: true
            ) {
                chooseFile()
            }
            .disabled(isBusy)
        }
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

    private var dropZoneHint: String {
        guard !coordinator.isProEntitlementActive else {
            return OffsendStrings.documentSanitizeDropHint
        }
        let freeLimit = Self.formattedMegabytes(DocumentProcessingLimits.freeMaximumFileByteCount)
        let proLimit = Self.formattedMegabytes(DocumentProcessingLimits.proMaximumFileByteCount)
        return OffsendStrings.documentSanitizeDropHintWithFileSizeLimit(freeLimit, proLimit)
    }

    private var privacyNote: some View {
        HStack(alignment: .top, spacing: OFSpacing.sm) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 13))
                .foregroundColor(.ofBlue)
                .padding(.top, 1)

            Text(OffsendStrings.documentSanitizePrivacyNote)
                .font(.system(size: 12))
                .foregroundColor(.ofTextSub)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(OFSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.ofBlueDim)
        .cornerRadius(OFRadius.md)
        .overlay(
            RoundedRectangle(cornerRadius: OFRadius.md)
                .stroke(Color.ofBlue.opacity(0.25), lineWidth: 1)
        )
    }

    private var emptyDropZone: some View {
        OFDropZone(
            title: OffsendStrings.documentSanitizeDropTitle,
            hint: dropZoneHint,
            isTargeted: isDropTargeted
        ) {
            guard !isBusy else { return }
            chooseFile()
        }
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: $isDropTargeted) { providers in
            guard !isBusy else { return false }
            return handleDrop(providers)
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

    private var safeDocumentBanner: some View {
        OFSemanticBanner(
            style: .success,
            icon: "checkmark.shield",
            title: OffsendStrings.documentSanitizeSafeTitle,
            subtitle: OffsendStrings.documentSanitizeSafeSubtitle
        )
    }

    private func selectedFileSummaryCard(_ fileURL: URL) -> some View {
        OFCardGroup {
            HStack(alignment: .center, spacing: OFSpacing.md) {
                OFIconTile(systemName: "doc.fill", tint: .ofTextMuted, size: 32, iconSize: 14)

                VStack(alignment: .leading, spacing: 2) {
                    Text(fileURL.lastPathComponent)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.ofText)
                        .lineLimit(1)

                    Text(displayPath(for: fileURL))
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundColor(.ofTextSub)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, OFSpacing.md)
            .padding(.vertical, 12)
        }
    }

    private func fileSummaryCard(_ result: DocumentAnalysisResult) -> some View {
        OFCardGroup {
            HStack(alignment: .center, spacing: OFSpacing.md) {
                OFIconTile(systemName: "doc.fill", tint: .ofTextMuted, size: 32, iconSize: 14)

                VStack(alignment: .leading, spacing: 2) {
                    Text(result.extracted.source.fileName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.ofText)
                        .lineLimit(1)

                    Text(displayPath(for: result.extracted.source.sourceURL ?? selectedFile))
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundColor(.ofTextSub)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 0)

                OFStatusCapsule(
                    style: riskBadgeStyle(for: result.assessment.level),
                    title: AppLocalization.riskLevelName(result.assessment.level).uppercased()
                )
            }
            .padding(.horizontal, OFSpacing.md)
            .padding(.vertical, 12)

            OFCardGroupDivider()

            VStack(alignment: .leading, spacing: 8) {
                summaryRow(
                    title: OffsendStrings.documentSanitizeSummaryCharacters,
                    value: "\(result.extracted.characterCount)"
                )
                summaryRow(
                    title: OffsendStrings.documentSanitizeSummaryEntities,
                    value: "\(result.detection.entities.count)"
                )
                if result.extracted.wasTruncated {
                    summaryRow(
                        title: OffsendStrings.documentSanitizeSummaryTruncated,
                        value: OffsendStrings.commonOn
                    )
                }
            }
            .padding(.horizontal, OFSpacing.md)
            .padding(.vertical, 12)
        }
    }

    private func summaryRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 12))
                .foregroundColor(.ofTextSub)
            Spacer()
            Text(value)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundColor(.ofText)
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

                Button {
                    if allEntitiesSelected(for: result) {
                        selectedEntityIDs.removeAll()
                    } else {
                        selectedEntityIDs = Set(result.detection.entities.map(\.id))
                    }
                    refreshSanitizePreview(for: result)
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
            .padding(.horizontal, 2)

            OFCardGroup {
                ForEach(Array(groupedEntities(for: result).enumerated()), id: \.element.type) { index, group in
                    if index > 0 { OFCardGroupDivider() }
                    entityGroupRow(group, result: result)
                }
            }

            if selectedEntityIDs.isEmpty {
                Text(OffsendStrings.documentSanitizeNoEntitiesSelected)
                    .font(.system(size: 11))
                    .foregroundColor(.ofAmberText)
            }

            HStack(spacing: OFSpacing.sm) {
                Text(OffsendStrings.documentSanitizeRiskScore)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.ofText)

                OFRiskMeterBar(
                    risk: uiRisk(for: result.assessment),
                    score: min(result.assessment.score, 100)
                )

                Spacer(minLength: 0)

                OFButton(
                    title: OffsendStrings.documentSanitizeRefreshAnalysis,
                    variant: .outline,
                    icon: "arrow.clockwise",
                    small: true
                ) {
                    analyze(fileURL: result.extracted.source.sourceURL ?? selectedFile!)
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
            .frame(maxWidth: .infinity, minHeight: 120, maxHeight: 220, alignment: .topLeading)
            .background(Color.ofBg2)
            .cornerRadius(OFRadius.md)
            .overlay(
                RoundedRectangle(cornerRadius: OFRadius.md)
                    .stroke(Color.ofBorder, lineWidth: 1)
            )
        }
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
                OFButton(
                    title: OffsendStrings.documentSanitizeSaveAs,
                    variant: .outline,
                    icon: "square.and.arrow.down",
                    small: true
                ) {
                    saveSafeText(for: result)
                }
                .disabled(isBusy || selectedEntityIDs.isEmpty)

                Spacer(minLength: 0)

                Text(OffsendStrings.documentSanitizeEntitiesSelected(selectedGroupCount))
                    .font(.system(size: 11))
                    .foregroundColor(.ofTextMuted)
                    .lineLimit(1)

                OFButton(
                    title: OffsendStrings.documentSanitizeCopySafeText,
                    variant: .primary,
                    icon: "doc.on.doc",
                    disabled: isBusy || selectedEntityIDs.isEmpty
                ) {
                    copySafeText(for: result)
                }
            }
            .padding(.horizontal, OFSpacing.xxl)
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
            refreshSanitizePreview(for: result)
        }
    }

    private func errorBanner(_ message: String) -> some View {
        OFSemanticBanner(
            style: .warning,
            icon: "exclamationmark.triangle.fill",
            title: OffsendStrings.documentSanitizeErrorTitle,
            subtitle: message
        )
    }

    private func statusBanner(_ message: String) -> some View {
        OFSemanticBanner(
            style: .info,
            icon: "info.circle.fill",
            title: OffsendStrings.documentSanitizeStatusTitle,
            subtitle: message
        )
    }

    private func preferredWindowHeight() -> CGFloat {
        var height: CGFloat
        switch windowContentPhase {
        case .empty:
            height = Layout.emptyStateHeight
        case .awaitingResult:
            height = Layout.awaitingResultHeight
        case .safeResult:
            height = Layout.safeResultHeight
        case .findingsResult:
            height = Layout.findingsResultHeight + Layout.footerHeight
        }

        if showsFileTooLargeBuyPro, selectedFile != nil {
            height += Layout.footerHeight
        }

        if windowContentPhase == .safeResult {
            if errorMessage != nil {
                height += Layout.bannerExtraHeight
            }
            if statusMessage != nil {
                height += Layout.bannerExtraHeight
            }
        }

        return height
    }

    private func shouldShowPinnedFooter(for result: DocumentAnalysisResult) -> Bool {
        !result.detection.entities.isEmpty
    }

    private func groupedEntities(for result: DocumentAnalysisResult) -> [EntityGroup] {
        Dictionary(grouping: result.detection.entities, by: \.type)
            .map { EntityGroup(type: $0.key, entities: $0.value.sorted { $0.range.lowerBound < $1.range.lowerBound }) }
            .sorted { $0.type.rawValue < $1.type.rawValue }
    }

    private func allEntitiesSelected(for result: DocumentAnalysisResult) -> Bool {
        selectedEntityIDs.count == result.detection.entities.count
    }

    private func displayPath(for url: URL?) -> String {
        guard let url else { return "—" }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let path = url.path
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.prompt = OffsendStrings.documentSanitizeChooseFile
        panel.allowedContentTypes = Self.supportedContentTypes

        if panel.runModal() == .OK, let url = panel.url {
            if selectedFile != nil {
                coordinator.openDocumentSanitize(for: url, source: "document_sanitize_choose_another")
            } else {
                selectFile(url)
            }
        }
    }

    private func bootstrapFromWindowPathIfNeeded() {
        guard let documentWindowPath,
              let url = fileURL(fromWindowPath: documentWindowPath) else {
            return
        }
        let standardizedURL = url.standardizedFileURL
        guard selectedFile?.standardizedFileURL != standardizedURL else { return }
        selectFile(standardizedURL)
    }

    private func fileURL(fromWindowPath path: String) -> URL? {
        let url = URL(fileURLWithPath: path)
        guard isSupportedFile(url) else { return nil }
        return url
    }

    private func prefillFileFromPasteboard() {
        guard selectedFile == nil, let fileURL = fileURLFromPasteboard() else { return }
        selectFile(fileURL)
    }

    private func selectFile(_ fileURL: URL) {
        let standardizedURL = fileURL.standardizedFileURL
        selectedFile = standardizedURL
        analysisResult = nil
        sanitizeResult = nil
        selectedEntityIDs = []
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

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }) else {
            return false
        }

        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            guard let url = fileURL(from: item), isSupportedFile(url) else { return }

            DispatchQueue.main.async {
                if self.selectedFile != nil {
                    self.coordinator.openDocumentSanitize(for: url, source: "document_sanitize_drop")
                } else {
                    self.selectFile(url)
                }
            }
        }
        return true
    }

    private func analyze(fileURL: URL) {
        let standardizedURL = fileURL.standardizedFileURL
        let token = UUID()

        selectedFile = standardizedURL
        analysisResult = nil
        sanitizeResult = nil
        selectedEntityIDs = []
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
                    refreshSanitizePreview(for: result)
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

    private func refreshSanitizePreview(for result: DocumentAnalysisResult) {
        guard !selectedEntityIDs.isEmpty else {
            sanitizeResult = nil
            return
        }

        let entities = result.detection.entities.filter { selectedEntityIDs.contains($0.id) }
        sanitizeResult = coordinator.previewSanitizedDocument(from: result, entities: entities)
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
                    at: result.extracted.source.sourceURL ?? selectedFile!,
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
                    at: result.extracted.source.sourceURL ?? selectedFile!,
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

    private func riskBadgeStyle(for level: RiskLevel) -> OFStatusBadgeStyle {
        switch level {
        case .low:
            return .pass
        case .medium:
            return .warn
        case .high, .critical:
            return .fail
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

    nonisolated private func isSupportedFile(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              !isDirectory.boolValue else {
            return false
        }
        return DocumentTextExtractorRegistry.supportedFileExtensions.contains(url.pathExtension.lowercased())
    }

    private func fileURLFromPasteboard() -> URL? {
        let pasteboard = NSPasteboard.general
        if let urls = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [NSURL] {
            return urls.map { $0 as URL }.first(where: { isSupportedFile($0) })
        }

        if let fileURLString = pasteboard.string(forType: .fileURL),
           let url = URL(string: fileURLString),
           url.isFileURL,
           isSupportedFile(url) {
            return url
        }

        return nil
    }
}

private struct EntityGroup {
    let type: SensitiveEntityType
    let entities: [SensitiveEntity]
}

private struct DocumentSanitizeWindowSizer: NSViewRepresentable {
    let size: NSSize

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            resizeWindow(for: view, animated: false)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            resizeWindow(for: nsView, animated: false)
        }
    }

    private func resizeWindow(for view: NSView, animated: Bool) {
        guard let window = view.window else { return }

        let current = window.contentRect(forFrameRect: window.frame).size
        guard abs(current.width - size.width) > 1 || abs(current.height - size.height) > 1 else {
            return
        }

        window.setContentSize(size, animated: animated)
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
