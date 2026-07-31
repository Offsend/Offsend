import AppUIKit
import AIDetectionCore
import DetectionCore
import SwiftUI

struct SettingsAIPanel: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @Environment(\.ofPalette) private var palette

    @State private var repositoryInput = ""
    @State private var remoteURLInput = ""
    @State private var tokenDraft = ""
    @State private var ollamaEndpointInput = "http://127.0.0.1:11434"
    @State private var selectedOllamaModel = ""
    @State private var showAdvancedSources = false
    @FocusState private var repositoryFieldFocused: Bool

    private var isDownloading: Bool {
        coordinator.aiModelDownloadProgress != nil
    }

    private var canEnableAIDetection: Bool {
        coordinator.selectedInstalledAIModel != nil
    }

    private var isAIDetectionToggleDisabled: Bool {
        if isDownloading { return true }
        if canEnableAIDetection { return false }
        return !coordinator.settings.aiDetectionEnabled
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            summaryCard
                .padding(.bottom, 22)

            detectorSection

            huggingFaceTokenSection

            addModelSection

            installedModelsSection
        }
    }

    // MARK: Summary

    private var summaryCard: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 9)
                    .fill(palette.blueDim)
                Image(systemName: "cpu")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(palette.blue)
            }
            .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(OffsendStrings.settingsAiSummaryTitle)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(palette.text)
                Text(OffsendStrings.settingsAiSummaryBody)
                    .font(.system(size: 11.5))
                    .foregroundColor(palette.textSub)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(palette.card)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(palette.border, lineWidth: 1))
        )
    }

    // MARK: Detector toggle

    private var detectorSection: some View {
        OFSettingsGroup(title: OffsendStrings.settingsAiSectionDetector) {
            OFSettingsRow(
                label: OffsendStrings.settingsAiEnableDetector,
                hint: canEnableAIDetection
                    ? OffsendStrings.settingsAiEnableDetectorHint
                    : OffsendStrings.settingsAiEnableDetectorDisabledHint,
                alignTop: true
            ) {
                OFToggle(
                    isOn: aiDetectionBinding,
                    size: 18
                )
                .disabled(isAIDetectionToggleDisabled)
            }

            if let selected = coordinator.selectedInstalledAIModel {
                OFSettingsGroupDivider()
                OFSettingsRow(
                    label: OffsendStrings.settingsAiSelectedModel,
                    hint: OffsendStrings.settingsAiSelectedModelHint,
                    alignTop: true
                ) {
                    OFSelectMenu(
                        selection: selectedModelBinding,
                        options: coordinator.installedAIModels.map {
                            OFSelectOption(value: $0.id, label: $0.displayName)
                        }
                    )
                    .disabled(isDownloading || coordinator.installedAIModels.count <= 1)
                }

                Text(modelMetaLine(for: selected))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(palette.textMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let loadStatus = aiModelLoadStatusLine {
                    Text(loadStatus.text)
                        .font(.system(size: 11))
                        .foregroundColor(loadStatus.color)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.bottom, 12)
                } else {
                    Spacer(minLength: 0)
                        .frame(height: 0)
                        .padding(.bottom, 12)
                }
            }
        }
    }

    private var aiModelLoadStatusLine: (text: String, color: Color)? {
        switch coordinator.aiModelLoadState {
        case .idle:
            return nil
        case .loading(let displayName):
            return (OffsendStrings.settingsAiModelLoadLoading(displayName), palette.textMuted)
        case .ready(let displayName):
            return (OffsendStrings.settingsAiModelLoadReady(displayName), palette.greenText)
        case .failed(let displayName, let message):
            return (OffsendStrings.settingsAiModelLoadFailed(displayName, message), palette.amberText)
        }
    }

    private var aiDetectionBinding: Binding<Bool> {
        Binding(
            get: {
                guard canEnableAIDetection else { return false }
                return coordinator.settings.aiDetectionEnabled
            },
            set: { newValue in
                coordinator.settings.aiDetectionEnabled = newValue
                coordinator.saveSettings()
                Task { await coordinator.reloadActiveAIModelIfNeeded(force: newValue) }
            }
        )
    }

    private var selectedModelBinding: Binding<String> {
        Binding(
            get: { coordinator.settings.selectedAIModelID ?? "" },
            set: { newValue in
                coordinator.selectAIModel(modelID: newValue.isEmpty ? nil : newValue)
            }
        )
    }

    // MARK: Hugging Face token

    private var huggingFaceTokenSection: some View {
        OFSettingsGroup(title: OffsendStrings.settingsAiSectionToken) {
            VStack(alignment: .leading, spacing: 12) {
                Text(OffsendStrings.settingsAiTokenHint)
                    .font(.system(size: 11.5))
                    .foregroundColor(palette.textSub)
                    .fixedSize(horizontal: false, vertical: true)

                SecureField(OffsendStrings.settingsAiTokenPlaceholder, text: $tokenDraft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5, design: .monospaced))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(palette.bg2)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(palette.border, lineWidth: 1))
                    )

                HStack(spacing: 8) {
                    OFCompactButton(title: OffsendStrings.settingsAiTokenSave, variant: .primary) {
                        coordinator.saveHuggingFaceToken(tokenDraft)
                        tokenDraft = ""
                    }
                    .disabled(tokenDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    if let preview = coordinator.huggingFaceTokenPreview {
                        OFCompactButton(title: OffsendStrings.settingsAiTokenClear(preview), variant: .outline) {
                            coordinator.clearHuggingFaceToken()
                            tokenDraft = ""
                        }
                    }
                }

                if let preview = coordinator.huggingFaceTokenPreview {
                    Text(OffsendStrings.settingsAiTokenSaved(preview))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(palette.greenText)
                }
            }
            .padding(.vertical, 14)
        }
    }

    // MARK: Add model

    private var addModelSection: some View {
        OFSettingsGroup(title: OffsendStrings.settingsAiSectionAddModel) {
            VStack(alignment: .leading, spacing: 14) {
                curatedModelsList

                OFSettingsGroupDivider()

                importActionsRow

                OFSettingsGroupDivider()

                downloadFormBlock

                OFSettingsGroupDivider()

                remoteURLFormBlock

                OFSettingsGroupDivider()

                advancedSourcesBlock
            }
            .padding(.vertical, 14)
        }
    }

    private var downloadFormBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(OffsendStrings.settingsAiDownloadDescription)
                .font(.system(size: 11.5))
                .foregroundColor(palette.textSub)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                TextField(OffsendStrings.settingsAiDownloadPlaceholder, text: $repositoryInput)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5, design: .monospaced))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(palette.bg2)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(palette.border, lineWidth: 1))
                    )
                    .focused($repositoryFieldFocused)
                    .disabled(isDownloading)

                if isDownloading {
                    OFCompactButton(title: OffsendStrings.settingsAiDownloadCancel, variant: .outline) {
                        coordinator.cancelAIModelDownload()
                    }
                } else {
                    OFCompactButton(title: OffsendStrings.settingsAiDownloadButton, variant: .primary) {
                        coordinator.downloadAIModel(from: repositoryInput)
                    }
                    .disabled(repositoryInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private var remoteURLFormBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(OffsendStrings.settingsAiRemoteURLDescription)
                .font(.system(size: 11.5))
                .foregroundColor(palette.textSub)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                TextField(OffsendStrings.settingsAiRemoteURLPlaceholder, text: $remoteURLInput)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5, design: .monospaced))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(palette.bg2)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(palette.border, lineWidth: 1))
                    )
                    .disabled(isDownloading)

                OFCompactButton(title: OffsendStrings.settingsAiRemoteURLButton, variant: .outline) {
                    coordinator.importAIModelFromURL(remoteURLInput)
                }
                .disabled(isDownloading || remoteURLInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private var importActionsRow: some View {
        HStack(spacing: 8) {
            OFCompactButton(title: OffsendStrings.settingsAiImportFolderButton, variant: .outline) {
                coordinator.importAIModelFolder()
            }
            .disabled(isDownloading)

            OFCompactButton(title: OffsendStrings.settingsAiImportManifestButton, variant: .outline) {
                coordinator.importAIModelManifest()
            }
            .disabled(isDownloading)

            OFCompactButton(title: OffsendStrings.settingsAiImportGGUFButton, variant: .outline) {
                coordinator.importGGUFFile()
            }
            .disabled(isDownloading)
        }
    }

    private var advancedSourcesBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                showAdvancedSources.toggle()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: showAdvancedSources ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                    Text(OffsendStrings.settingsAiAdvancedSourcesTitle)
                        .font(.system(size: 11.5, weight: .semibold))
                }
                .foregroundColor(palette.textSub)
            }
            .buttonStyle(.plain)

            if showAdvancedSources {
                Text(OffsendStrings.settingsAiOllamaDescription)
                    .font(.system(size: 11.5))
                    .foregroundColor(palette.textSub)
                    .fixedSize(horizontal: false, vertical: true)

                TextField(OffsendStrings.settingsAiOllamaEndpointPlaceholder, text: $ollamaEndpointInput)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5, design: .monospaced))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(palette.bg2)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(palette.border, lineWidth: 1))
                    )
                    .disabled(isDownloading)

                HStack(spacing: 8) {
                    OFCompactButton(title: OffsendStrings.settingsAiOllamaRefreshButton, variant: .outline) {
                        coordinator.refreshOllamaModels(endpoint: ollamaEndpointInput)
                    }
                    .disabled(isDownloading)

                    if !coordinator.ollamaDiscoveredModels.isEmpty {
                        OFSelectMenu(
                            selection: $selectedOllamaModel,
                            options: coordinator.ollamaDiscoveredModels.map {
                                OFSelectOption(value: $0, label: $0)
                            }
                        )
                        .disabled(isDownloading)

                        OFCompactButton(title: OffsendStrings.settingsAiOllamaConnectButton, variant: .primary) {
                            coordinator.connectOllamaModel(endpoint: ollamaEndpointInput, modelName: selectedOllamaModel)
                        }
                        .disabled(isDownloading || selectedOllamaModel.isEmpty)
                    }
                }

                Text(OffsendStrings.settingsAiGgufHint)
                    .font(.system(size: 11))
                    .foregroundColor(palette.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var curatedModelsList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(OffsendStrings.settingsAiCatalogTitle)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundColor(palette.textSub)
                .textCase(.uppercase)

            ForEach(RecommendedAIModelCatalog.models) { model in
                curatedModelRow(model)
            }
        }
    }

    private func curatedModelRow(_ model: RecommendedAIModel) -> some View {
        let installed = coordinator.installedAIModels.contains { $0.id == model.repositoryID }
        return HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(model.title)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundColor(palette.text)
                    Text(OffsendStrings.settingsAiCatalogVerifiedBadge)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(palette.greenText)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(palette.greenDim))
                    if model.requiresToken {
                        Text(OffsendStrings.settingsAiCatalogRequiresToken)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(palette.amberText)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(palette.amberDim))
                    }
                }
                Text(model.detail)
                    .font(.system(size: 11))
                    .foregroundColor(palette.textMuted)
                Text(model.repositoryID)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundColor(palette.textSub)
            }

            Spacer(minLength: 8)

            if installed {
                Text(OffsendStrings.settingsAiCatalogInstalled)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(palette.textMuted)
            } else {
                OFCompactButton(title: OffsendStrings.settingsAiCatalogDownload, variant: .outline) {
                    repositoryInput = model.repositoryID
                    coordinator.downloadRecommendedAIModel(model)
                }
                .disabled(isDownloading)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(palette.bg2)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(palette.border, lineWidth: 1))
        )
    }

    // MARK: Installed models

    private var installedModelsSection: some View {
        OFSettingsGroup(title: OffsendStrings.settingsAiSectionInstalled) {
            if coordinator.installedAIModels.isEmpty {
                Text(OffsendStrings.settingsAiInstalledEmpty)
                    .font(.system(size: 12))
                    .foregroundColor(palette.textSub)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
            } else {
                ForEach(Array(coordinator.installedAIModels.enumerated()), id: \.element.id) { index, model in
                    installedModelRow(model)
                    if index < coordinator.installedAIModels.count - 1 {
                        OFSettingsGroupDivider()
                    }
                }
            }
        }
    }

    private func installedModelRow(_ model: InstalledAIModel) -> some View {
        let isSelected = coordinator.settings.selectedAIModelID == model.id
        return HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(model.displayName)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundColor(palette.text)
                    if isSelected {
                        Text(OffsendStrings.settingsAiActiveBadge)
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundColor(palette.blue)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(palette.blueDim))
                    }
                    Text(model.isVerified ? OffsendStrings.settingsAiCatalogVerifiedBadge : OffsendStrings.settingsAiCustomBadge)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(model.isVerified ? palette.greenText : palette.textSub)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(model.isVerified ? palette.greenDim : palette.bg2))
                    Text(coordinator.aiModelFormatLabel(model.format))
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(palette.textSub)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(palette.bg2))
                }
                Text(coordinator.aiModelSourceLabel(model))
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundColor(palette.textSub)
                Text(modelMetaLine(for: model))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(palette.textMuted)
            }

            Spacer(minLength: 8)

            HStack(spacing: 8) {
                if !isSelected {
                    OFCompactButton(title: OffsendStrings.settingsAiUseModel, variant: .outline) {
                        coordinator.selectAIModel(modelID: model.id)
                    }
                    .disabled(isDownloading)
                }

                OFCompactButton(title: OffsendStrings.settingsAiDeleteModel, variant: .outline) {
                    coordinator.deleteInstalledAIModel(modelID: model.id)
                }
                .disabled(isDownloading)
            }
        }
        .padding(.vertical, 12)
    }

    private func modelMetaLine(for model: InstalledAIModel) -> String {
        let size = coordinator.formattedAIModelByteSize(model.totalByteSize)
        if case .huggingFace(_, let revision) = model.source {
            return OffsendStrings.settingsAiModelMeta(size, revision)
        }
        return size
    }
}

// MARK: - Pinned download progress

struct SettingsAIDownloadProgressBanner: View {
    static let pinnedBarHeight: CGFloat = 45

    @EnvironmentObject private var coordinator: AppCoordinator
    @Environment(\.ofPalette) private var palette

    let progress: AIModelDownloadProgress

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(OffsendStrings.settingsAiDownloadActive(progress.modelID))
                    .font(.system(size: 10.5))
                    .foregroundColor(palette.textMuted)
                    .lineLimit(1)

                ProgressView(value: max(progress.fractionCompleted, 0.02))
                    .progressViewStyle(.linear)
                    .scaleEffect(x: 1, y: 0.55, anchor: .center)
                    .frame(height: 4)
            }

            Spacer(minLength: 8)

            OFCompactButton(title: OffsendStrings.settingsAiDownloadCancel, variant: .outline) {
                coordinator.cancelAIModelDownload()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
