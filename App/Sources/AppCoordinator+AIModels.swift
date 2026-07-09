import AppKit
import DetectionCore
import AIDetectionCore
import Foundation
import StorageCore
import UniformTypeIdentifiers

extension AppCoordinator {
    func reloadHuggingFaceTokenState() {
        let token = (try? HuggingFaceTokenStore.shared.loadToken()).flatMap { $0 }
        if let token {
            hasHuggingFaceToken = true
            huggingFaceTokenPreview = HuggingFaceTokenStore.maskedPreview(for: token)
        } else {
            hasHuggingFaceToken = false
            huggingFaceTokenPreview = nil
        }
    }

    func saveHuggingFaceToken(_ token: String) {
        do {
            try HuggingFaceTokenStore.shared.saveToken(token)
            reloadHuggingFaceTokenState()
            lastStatusMessage = OffsendStrings.statusAiModelTokenSaved
        } catch {
            lastStatusMessage = OffsendStrings.statusAiModelTokenSaveFailed(error.localizedDescription)
        }
    }

    func clearHuggingFaceToken() {
        do {
            try HuggingFaceTokenStore.shared.deleteToken()
            reloadHuggingFaceTokenState()
        } catch {
            lastStatusMessage = OffsendStrings.statusAiModelTokenSaveFailed(error.localizedDescription)
        }
    }

    func reloadInstalledAIModels() {
        installedAIModels = (try? aiModelStore.loadInstalledAIModels()) ?? []
        reconcileAIDetectionSettings()
        Task { await reloadActiveAIModelIfNeeded(force: aiModelSessionManager.hasActiveSessions) }
    }

    func selectAIModel(modelID: String?) {
        settings.selectedAIModelID = modelID
        saveSettings()
        Task { await reloadActiveAIModelIfNeeded(force: aiModelSessionManager.hasActiveSessions) }
    }

    func beginAIModelSession() {
        aiModelSessionManager.beginSession()
    }

    func endAIModelSession() {
        aiModelSessionManager.endSession()
    }

    func ensureAIModelLoadedForDetection() async {
        guard wantsAIDetection else { return }
        aiModelSessionManager.cancelScheduledUnload()
        await reloadActiveAIModelIfNeeded(force: true)
    }

    func unloadAIModelAfterIdleTimeout() {
        unloadAIModel()
        aiModelLoadState = .idle
    }

    /// Updates the MainActor mirror immediately; the actor unload happens asynchronously.
    private func unloadAIModel() {
        loadedAIModelID = nil
        let registry = aiModelRegistry
        Task { await registry.unload() }
    }

    func cancelAIModelDownload() {
        aiModelDownloadTask?.cancel()
        aiModelDownloadTask = nil
        aiModelDownloadProgress = nil
    }

    func deleteInstalledAIModel(modelID: String) {
        cancelAIModelDownload()
        guard let model = installedAIModels.first(where: { $0.id == modelID }) else { return }
        do {
            try AIModelFileStore.deleteModelFiles(localDirectoryName: model.localDirectoryName)
            let models = installedAIModels.filter { $0.id != modelID }
            try aiModelStore.saveInstalledAIModels(models)
            installedAIModels = models
            if settings.selectedAIModelID == modelID {
                settings.selectedAIModelID = models.first?.id
                if models.isEmpty {
                    settings.aiDetectionEnabled = false
                }
                saveSettings()
            }
            if loadedAIModelID == modelID {
                unloadAIModel()
                aiModelLoadState = .idle
            }
        } catch {
            lastStatusMessage = OffsendStrings.statusAiModelDeleteFailed(error.localizedDescription)
        }
    }

    func downloadRecommendedAIModel(_ model: RecommendedAIModel) {
        importAIModel(
            reference: .huggingFace(
                rawReference: model.repositoryID,
                displayName: model.title,
                revision: "main",
                requiresToken: model.requiresToken
            )
        )
    }

    func downloadAIModel(from rawReference: String) {
        importAIModel(
            reference: .huggingFace(
                rawReference: rawReference,
                displayName: nil,
                revision: "main",
                requiresToken: false
            )
        )
    }

    func importAIModelFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = OffsendStrings.settingsAiImportFolderButton
        panel.message = OffsendStrings.settingsAiImportFolderMessage

        guard panel.runModal() == .OK, let url = panel.url else { return }
        importAIModel(reference: .folder(url))
    }

    func importAIModelManifest() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.json]
        panel.prompt = OffsendStrings.settingsAiImportManifestButton

        guard panel.runModal() == .OK, let url = panel.url else { return }
        importAIModel(reference: .manifest(url))
    }

    func importGGUFFile() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [UTType(filenameExtension: "gguf") ?? .data]
        panel.prompt = OffsendStrings.settingsAiImportGGUFButton

        guard panel.runModal() == .OK, let url = panel.url else { return }
        importAIModel(reference: .ggufFile(url))
    }

    func refreshOllamaModels(endpoint: String) {
        Task {
            do {
                let client = OllamaClient(baseURL: try OllamaClient.normalizedLocalEndpoint(endpoint))
                let models = try await client.listModels()
                ollamaDiscoveredModels = models.map(\.name).sorted()
                lastStatusMessage = OffsendStrings.statusOllamaModelsListed(ollamaDiscoveredModels.count)
            } catch {
                ollamaDiscoveredModels = []
                lastStatusMessage = OffsendStrings.statusOllamaUnreachable(CoreErrorLocalization.message(for: error))
            }
        }
    }

    func connectOllamaModel(endpoint: String, modelName: String) {
        importAIModel(reference: .ollama(endpoint: endpoint, modelName: modelName))
    }

    func importAIModelFromURL(_ urlString: String) {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), url.scheme?.lowercased() == "https" else {
            reportAIModelImportFailure(.invalidURL)
            return
        }
        importAIModel(reference: .remoteURL(url))
    }

    private func importAIModel(reference: AIModelImportReference) {
        if case let .ollama(endpoint, modelName) = reference,
           let url = try? OllamaClient.normalizedLocalEndpoint(endpoint),
           let modelID = try? OllamaModelImporter.modelID(endpoint: url, modelName: modelName) {
            if installedAIModels.contains(where: { $0.id == modelID }) {
                reportAIModelImportFailure(.alreadyInstalled(modelName))
                return
            }
        }

        if case let .huggingFace(rawReference, _, _, requiresToken) = reference {
            if requiresToken, !hasHuggingFaceToken {
                reportAIModelImportFailure(.gatedRequiresToken)
                return
            }
            if let repositoryID = HuggingFaceRepository.parseRepositoryID(rawReference),
               installedAIModels.contains(where: { $0.id == repositoryID }) {
                reportAIModelImportFailure(.alreadyInstalled(repositoryID))
                return
            }
        }

        let progressID: String = {
            switch reference {
            case .huggingFace(let raw, _, _, _):
                return HuggingFaceRepository.parseRepositoryID(raw) ?? UUID().uuidString
            case .folder:
                return UUID().uuidString
            case .remoteURL(let url):
                return url.lastPathComponent
            case .manifest(let url):
                return url.deletingPathExtension().lastPathComponent
            case .ollama(let endpoint, let modelName):
                if let url = try? OllamaClient.normalizedLocalEndpoint(endpoint),
                   let modelID = try? OllamaModelImporter.modelID(endpoint: url, modelName: modelName) {
                    return modelID
                }
                return modelName
            case .ggufFile(let url):
                return url.deletingPathExtension().lastPathComponent
            }
        }()

        cancelAIModelDownload()
        aiModelDownloadProgress = AIModelDownloadProgress(modelID: progressID)

        aiModelDownloadTask = Task { [weak self] in
            guard let self else { return }
            do {
                if case let .huggingFace(rawReference, _, revision, _) = reference,
                   let repositoryID = HuggingFaceRepository.parseRepositoryID(rawReference) {
                    let token = try HuggingFaceTokenStore.shared.loadToken()
                    let downloader = HuggingFaceModelDownloader(accessToken: token)
                    let inspection = try await downloader.inspectRemoteRepository(
                        repositoryID: repositoryID,
                        revision: revision
                    )
                    guard inspection.isRunnable else {
                        throw AIModelCatalogError.incompatibleModel(
                            inspection.reason ?? "This Hugging Face repo has no runnable ONNX or Core ML model."
                        )
                    }
                }

                let token = try HuggingFaceTokenStore.shared.loadToken()
                let credentials = AIModelCredentials(huggingFaceToken: token)
                let coordinator = AIModelImportCoordinator()
                let result = try await coordinator.importModel(reference: reference, credentials: credentials) { progress in
                    Task { @MainActor in
                        self.aiModelDownloadProgress = progress
                    }
                }

                var models = installedAIModels.filter { $0.id != result.model.id }
                models.append(result.model)
                models.sort { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
                try aiModelStore.saveInstalledAIModels(models)
                installedAIModels = models

                if settings.selectedAIModelID == nil {
                    settings.selectedAIModelID = result.model.id
                    saveSettings()
                }

                aiModelDownloadProgress = nil
                if !result.checksumWarnings.isEmpty {
                    lastStatusMessage = OffsendStrings.statusAiModelImportedWithWarnings(
                        result.model.displayName,
                        result.checksumWarnings.count
                    )
                } else {
                    lastStatusMessage = OffsendStrings.statusAiModelDownloaded(result.model.displayName)
                }

                await reloadActiveAIModelIfNeeded(force: aiModelSessionManager.hasActiveSessions)
            } catch is CancellationError {
                aiModelDownloadProgress = nil
                cleanupFailedImport(for: reference)
            } catch let error as AIModelCatalogError {
                aiModelDownloadProgress = nil
                cleanupFailedImport(for: reference)
                reportAIModelImportFailure(AIModelImportAlert.failure(for: error, hasHuggingFaceToken: hasHuggingFaceToken))
            } catch {
                aiModelDownloadProgress = nil
                cleanupFailedImport(for: reference)
                reportAIModelImportFailure(.downloadFailed(CoreErrorLocalization.message(for: error)))
            }
            aiModelDownloadTask = nil
        }
    }

    func reloadActiveAIModelIfNeeded(force: Bool = false) async {
        guard wantsAIDetection,
              let modelID = settings.selectedAIModelID,
              let model = installedAIModels.first(where: { $0.id == modelID }) else {
            unloadAIModel()
            aiModelLoadState = .idle
            return
        }

        let shouldLoad = force
            || aiModelSessionManager.hasActiveSessions
            || loadedAIModelID != nil
        guard shouldLoad else {
            aiModelLoadState = .idle
            return
        }

        let directory = AIModelFileStore.modelDirectory(for: model.localDirectoryName)
        guard FileManager.default.fileExists(atPath: directory.path) else {
            unloadAIModel()
            aiModelLoadState = .failed(
                displayName: model.displayName,
                message: OffsendStrings.statusAiModelFilesMissing
            )
            lastStatusMessage = OffsendStrings.statusAiModelLoadFailed(OffsendStrings.statusAiModelFilesMissing)
            return
        }

        aiModelLoadState = .loading(displayName: model.displayName)
        do {
            try await aiModelRegistry.load(model: model, directory: directory)
            loadedAIModelID = model.id
            aiModelLoadState = .ready(displayName: model.displayName)
            if aiModelSessionManager.hasActiveSessions {
                lastStatusMessage = OffsendStrings.statusAiModelLoadReady(model.displayName)
            } else {
                aiModelSessionManager.scheduleUnloadIfIdle()
            }
        } catch {
            unloadAIModel()
            let message = CoreErrorLocalization.message(for: error)
            aiModelLoadState = .failed(displayName: model.displayName, message: message)
            lastStatusMessage = OffsendStrings.statusAiModelLoadFailed(message)
        }
    }

    private var wantsAIDetection: Bool {
        guard settings.aiDetectionEnabled,
              let modelID = settings.selectedAIModelID else { return false }
        return installedAIModels.contains { $0.id == modelID }
    }

    func detectionOptions(maximumLength: Int = 50_000) -> DetectionOptions {
        let aiEnabled = wantsAIDetection
            && loadedAIModelID != nil
            && loadedAIModelID == settings.selectedAIModelID
        return DetectionOptions(
            enabledTypes: settings.enabledDetectors,
            customDictionaries: tariffFeatures.customDictionaries ? customDictionaries : [],
            maximumLength: maximumLength,
            aiDetectionEnabled: aiEnabled,
            selectedAIModelID: settings.selectedAIModelID
        )
    }

    var selectedInstalledAIModel: InstalledAIModel? {
        guard let modelID = settings.selectedAIModelID else { return nil }
        return installedAIModels.first { $0.id == modelID }
    }

    func formattedAIModelByteSize(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    func aiModelSourceLabel(_ model: InstalledAIModel) -> String {
        switch model.source {
        case .huggingFace(let repositoryID, _):
            return repositoryID
        case .importedFolder(let path):
            return (path as NSString).lastPathComponent
        case .remoteURL(let url):
            return url.host ?? url.absoluteString
        case .manifest(let url):
            return url.lastPathComponent
        case .ollama(let endpoint, let modelName):
            return "\(endpoint.host ?? endpoint.absoluteString) · \(modelName)"
        }
    }

    func aiModelFormatLabel(_ format: AIModelFormat) -> String {
        switch format {
        case .huggingFaceTransformers:
            return OffsendStrings.settingsAiFormatHuggingFace
        case .onnxTokenClassification:
            return OffsendStrings.settingsAiFormatOnnx
        case .coreML:
            return OffsendStrings.settingsAiFormatCoreML
        case .gguf:
            return OffsendStrings.settingsAiFormatGguf
        case .ollamaAPI:
            return OffsendStrings.settingsAiFormatOllama
        }
    }

    private func reportAIModelImportFailure(_ failure: AIModelImportFailure) {
        let statusMessage = AIModelImportAlert.statusMessage(for: failure)
        lastStatusMessage = statusMessage
        AIModelImportAlert.present(failure)
    }

    func reconcileAIDetectionSettings() {
        let hasValidSelection = settings.selectedAIModelID.map { modelID in
            installedAIModels.contains { $0.id == modelID }
        } ?? false

        var didChange = false

        if !hasValidSelection {
            let fallbackID = installedAIModels.first?.id
            if settings.selectedAIModelID != fallbackID {
                settings.selectedAIModelID = fallbackID
                didChange = true
            }
            if settings.aiDetectionEnabled {
                settings.aiDetectionEnabled = false
                didChange = true
            }
        }

        if didChange {
            saveSettings()
        }
    }

    private func cleanupFailedImport(for reference: AIModelImportReference) {
        switch reference {
        case .huggingFace(let rawReference, _, _, _):
            if let repositoryID = HuggingFaceRepository.parseRepositoryID(rawReference) {
                try? AIModelFileStore.deleteModelFiles(localDirectoryName: HuggingFaceRepository.directoryName(for: repositoryID))
            }
        case .folder, .remoteURL, .manifest, .ollama, .ggufFile:
            break
        }
    }
}
