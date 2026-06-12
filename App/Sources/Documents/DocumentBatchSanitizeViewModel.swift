import AppKit
import Combine
import DocumentCore
import Foundation

@MainActor
final class DocumentBatchSanitizeViewModel: ObservableObject {
    @Published private(set) var activeDocumentIndex = 0
    @Published private(set) var layoutResetToken = UUID()
    @Published private(set) var isSavingAll = false

    let fileURLs: [URL]
    private(set) var documentViewModels: [DocumentSanitizeViewModel]

    private weak var coordinator: AppCoordinator?
    private var cancellables = Set<AnyCancellable>()
    private var analysisTask: Task<Void, Never>?
    private var saveAllTask: Task<Void, Never>?
    private var lastActiveLayoutSignature: String?

    private enum Analysis {
        static let maxConcurrent = 2
    }

    var showsDocumentTabs: Bool {
        fileURLs.count > 1
    }

    var activeViewModel: DocumentSanitizeViewModel {
        documentViewModels[activeDocumentIndex]
    }

    var activeDocumentName: String {
        activeViewModel.selectedFile.lastPathComponent
    }

    var activeOverlayMode: DocumentSanitizeWorkingOverlayMode? {
        if isSavingAll { return .sanitizing }
        let viewModel = activeViewModel
        if viewModel.isSanitizing { return .sanitizing }
        if viewModel.isAnalyzing { return .analyzing }
        if viewModel.isRefreshingPdfPreview { return .refreshingPreview }
        return nil
    }

    var showsWorkingOverlay: Bool {
        activeOverlayMode != nil
    }

    var isActiveDocumentBusy: Bool {
        isSavingAll || activeViewModel.isBusy
    }

    var canSaveAllPrepared: Bool {
        guard showsDocumentTabs, !isSavingAll else { return false }
        return !saveableDocuments.isEmpty
    }

    var batchAnalysisProgress: DocumentBatchAnalysisProgress? {
        guard showsDocumentTabs else { return nil }
        let totalCount = documentViewModels.count
        let finishedCount = documentViewModels.filter(isAnalysisFinished).count
        guard finishedCount < totalCount else { return nil }
        return DocumentBatchAnalysisProgress(finishedCount: finishedCount, totalCount: totalCount)
    }

    init(fileURLs: [URL]) {
        let standardizedURLs = fileURLs.map(\.standardizedFileURL)
        self.fileURLs = standardizedURLs
        documentViewModels = standardizedURLs.map { DocumentSanitizeViewModel(fileURL: $0) }
    }

    func bind(coordinator: AppCoordinator) {
        self.coordinator = coordinator
        cancellables.removeAll()
        for viewModel in documentViewModels {
            viewModel.bind(coordinator: coordinator)
            // Forward only status-level changes: preview/selection updates of a document
            // are observed directly by its subviews and must not re-render the whole window.
            batchStatusPublisher(for: viewModel)
                .sink { [weak self] in
                    guard let self else { return }
                    self.objectWillChange.send()
                    self.syncLayoutToActiveDocument()
                }
                .store(in: &cancellables)
        }
    }

    func handleAppear() {
        coordinator?.beginAIModelSession()
        syncLayoutToActiveDocument(force: true)
        startAnalysisPipeline()
    }

    func releaseSession() {
        analysisTask?.cancel()
        analysisTask = nil
        saveAllTask?.cancel()
        saveAllTask = nil
        isSavingAll = false
        cancellables.removeAll()
        for viewModel in documentViewModels {
            viewModel.releaseSession()
        }
        coordinator?.endAIModelSession()
    }

    func selectDocument(at index: Int) {
        guard documentViewModels.indices.contains(index) else { return }
        guard activeDocumentIndex != index else { return }
        activeDocumentIndex = index
        syncLayoutToActiveDocument(force: true)
    }

    func tabStatus(for index: Int) -> DocumentBatchTabStatus {
        let viewModel = documentViewModels[index]
        if viewModel.isSanitizing || viewModel.isRefreshingPdfPreview {
            return .analyzing
        }
        if viewModel.isAnalyzing {
            return .analyzing
        }
        if viewModel.showsFileTooLargeBuyPro {
            return .tooLarge
        }
        if viewModel.errorMessage != nil, viewModel.analysisResult == nil {
            return .error
        }
        if let result = viewModel.analysisResult {
            let count = result.detection.entities.count
            return count > 0 ? .findings(count: count) : .safe
        }
        return .pending
    }

    func preferredWindowHeight() -> CGFloat {
        var height = activeViewModel.preferredWindowHeight()
        if showsDocumentTabs {
            height += DocumentSanitizeLayout.documentTabBarHeight
            height += DocumentSanitizeLayout.tabSectionSpacing
            if batchAnalysisProgress != nil {
                height += DocumentSanitizeLayout.batchProgressHeight
            }
        }
        return height
    }

    func showsFindingsFooter(for viewModel: DocumentSanitizeViewModel) -> Bool {
        viewModel.analysisResult != nil
    }

    func showsFileTooLargeFooter(for viewModel: DocumentSanitizeViewModel) -> Bool {
        viewModel.showsFileTooLargeBuyPro
    }

    func saveAllPrepared() {
        guard canSaveAllPrepared else { return }

        let savableDocuments = saveableDocuments
        guard !savableDocuments.isEmpty else { return }

        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = OffsendStrings.documentSanitizeSaveAllPreparedChooseFolder
        panel.message = OffsendStrings.documentSanitizeSaveAllPreparedMessage(savableDocuments.count)

        guard panel.runModal() == .OK, let directoryURL = panel.url else { return }

        isSavingAll = true
        saveAllTask?.cancel()
        saveAllTask = Task {
            var savedCount = 0
            var lastError: Error?

            for (viewModel, result) in savableDocuments {
                if Task.isCancelled { break }
                do {
                    try await viewModel.saveDocument(for: result, to: directoryURL)
                    savedCount += 1
                } catch {
                    lastError = error
                }
            }

            isSavingAll = false

            if savedCount > 0 {
                activeViewModel.reportSavedAllPrepared(
                    count: savedCount,
                    folderName: directoryURL.lastPathComponent
                )
            }

            if let lastError, savedCount == 0 {
                activeViewModel.reportProcessingError(lastError)
            }
        }
    }

    private var saveableDocuments: [(DocumentSanitizeViewModel, DocumentAnalysisResult)] {
        documentViewModels.compactMap { viewModel in
            guard let result = viewModel.analysisResult,
                  viewModel.canSaveDocument(for: result) else {
                return nil
            }
            return (viewModel, result)
        }
    }

    private func startAnalysisPipeline() {
        analysisTask?.cancel()
        analysisTask = Task {
            await analyzeDocumentsWithConcurrencyLimit()
        }
    }

    private func analyzeDocumentsWithConcurrencyLimit() async {
        let pendingViewModels = documentViewModels.filter { !isAnalysisFinished($0) }
        guard !pendingViewModels.isEmpty else { return }

        await withTaskGroup(of: Void.self) { group in
            var nextIndex = 0

            while nextIndex < min(Analysis.maxConcurrent, pendingViewModels.count) {
                let viewModel = pendingViewModels[nextIndex]
                nextIndex += 1
                group.addTask { await self.analyzeDocument(viewModel) }
            }

            while await group.next() != nil {
                guard !Task.isCancelled, nextIndex < pendingViewModels.count else { continue }
                let viewModel = pendingViewModels[nextIndex]
                nextIndex += 1
                group.addTask { await self.analyzeDocument(viewModel) }
            }
        }
    }

    private func analyzeDocument(_ viewModel: DocumentSanitizeViewModel) async {
        await viewModel.runInitialAnalysis()
        guard !Task.isCancelled else { return }
        syncLayoutToActiveDocument(force: true)
    }

    private func isAnalysisFinished(_ viewModel: DocumentSanitizeViewModel) -> Bool {
        viewModel.analysisResult != nil
            || viewModel.showsFileTooLargeBuyPro
            || (viewModel.errorMessage != nil && !viewModel.isAnalyzing)
    }

    private func batchStatusPublisher(
        for viewModel: DocumentSanitizeViewModel
    ) -> AnyPublisher<Void, Never> {
        Publishers.MergeMany(
            viewModel.$isAnalyzing.removeDuplicates().map { _ in () }.eraseToAnyPublisher(),
            viewModel.$isSanitizing.removeDuplicates().map { _ in () }.eraseToAnyPublisher(),
            viewModel.$isRefreshingPdfPreview.removeDuplicates().map { _ in () }.eraseToAnyPublisher(),
            viewModel.$showsFileTooLargeBuyPro.removeDuplicates().map { _ in () }.eraseToAnyPublisher(),
            viewModel.$analysisResult.map { _ in () }.eraseToAnyPublisher(),
            viewModel.$errorMessage.removeDuplicates().map { _ in () }.eraseToAnyPublisher()
        )
        .eraseToAnyPublisher()
    }

    private func syncLayoutToActiveDocument(force: Bool = false) {
        let signature = activeLayoutSignature
        guard force || signature != lastActiveLayoutSignature else { return }
        lastActiveLayoutSignature = signature
        layoutResetToken = UUID()
    }

    private var activeLayoutSignature: String {
        let viewModel = activeViewModel
        let showsFooter = showsFileTooLargeFooter(for: viewModel)
            || showsFindingsFooter(for: viewModel)
        let batchProgress = batchAnalysisProgress.map { "\($0.finishedCount)/\($0.totalCount)" } ?? "done"
        return [
            String(describing: viewModel.windowContentPhase),
            showsFooter ? "footer" : "no-footer",
            viewModel.isBusy ? "busy" : "idle",
            batchProgress
        ].joined(separator: "|")
    }
}
