import AppKit
import AppUIKit
import LicenseCore
import SwiftUI
import UniformTypeIdentifiers
import WorkspacePolicyCore

struct DirectoryCheckView: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @State private var selectedDirectory: URL?
    @State private var auditResult: AIWorkspacePrivacyAuditResult?
    @State private var isDropTargeted = false
    @State private var fixMessage: String?

    private let auditor = AIWorkspacePrivacyAuditor()
    private let fixer = AIWorkspacePrivacyFixer()

    private enum Layout {
        static let windowWidth: CGFloat = 640
        static let baseHeight: CGFloat = 500
        static let freeBannerExtra: CGFloat = 88
        static let auditResultsExtra: CGFloat = 140
        static let maxHeight: CGFloat = 860
    }

    private var auditConfiguration: AIWorkspacePrivacyAuditConfiguration {
        coordinator.tariffFeatures.workspaceAuditFull ? .default : .freeTier
    }

    private var canAutofix: Bool {
        coordinator.licenseState.plan == .pro && coordinator.tariffFeatures.workspaceAuditAutofix
    }

    var body: some View {
        let features = coordinator.tariffFeatures
        let plan = coordinator.licenseState.plan
        let windowHeight = preferredWindowHeight(
            showsFreeBanner: !features.workspaceAuditFull,
            hasAuditResult: auditResult != nil
        )
        let windowSize = NSSize(width: Layout.windowWidth, height: windowHeight)

        VStack(spacing: 0) {
            header
                .padding(.horizontal, OFSpacing.xxl)
                .padding(.top, OFSpacing.xl)
                .padding(.bottom, OFSpacing.md)

            OFDivider()

            ScrollView {
                VStack(alignment: .leading, spacing: OFSpacing.lg) {
                    Text(OffsendStrings.directoryCheckDescription)
                        .font(.system(size: 14))
                        .foregroundColor(.ofTextSub)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)

                    if !features.workspaceAuditFull {
                        freeScopeNote
                    }

                    dropZone

                    if let auditResult {
                        VStack(alignment: .leading, spacing: OFSpacing.lg) {
                            resultSummary(auditResult, features: features, canAutofix: canAutofix)
                            findingsSection(auditResult, features: features)
                        }
                        .id(plan)
                    } else {
                        emptyState
                    }
                }
                .padding(OFSpacing.xxl)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(
            width: Layout.windowWidth,
            height: windowHeight,
            alignment: .top
        )
        .background(Color.ofBg1)
        .background(DirectoryCheckWindowSizer(size: windowSize))
        .onAppear {
            prefillDirectoryFromPasteboard()
        }
        .onChange(of: coordinator.licenseState) { _ in
            guard let selectedDirectory else { return }
            audit(directoryURL: selectedDirectory)
        }
        .animation(.easeInOut(duration: 0.2), value: windowHeight)
    }

    private func preferredWindowHeight(showsFreeBanner: Bool, hasAuditResult: Bool) -> CGFloat {
        var height = Layout.baseHeight
        if showsFreeBanner {
            height += Layout.freeBannerExtra
        }
        if hasAuditResult {
            height += Layout.auditResultsExtra
        }
        return min(height, Layout.maxHeight)
    }

    private var freeScopeNote: some View {
        HStack(alignment: .top, spacing: OFSpacing.sm) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 13))
                .foregroundColor(.ofBlue)
                .padding(.top, 1)

            Text(OffsendStrings.directoryCheckFreeScopeNote)
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

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.ofBlueDim)
                    .frame(width: 44, height: 44)

                Image(systemName: "folder.badge.gearshape")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.ofBlue)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(OffsendStrings.directoryCheckTitle)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.ofText)

                Text(OffsendStrings.directoryCheckSubtitle)
                    .font(.system(size: 12))
                    .foregroundColor(.ofTextMuted)
            }

            Spacer()

            OFButton(title: OffsendStrings.directoryCheckChooseFolder, variant: .outline, icon: "folder", small: true) {
                chooseDirectory()
            }
        }
    }

    private var dropZone: some View {
        VStack(spacing: OFSpacing.md) {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 32, weight: .semibold))
                .foregroundColor(isDropTargeted ? .ofBlue : .ofTextMuted)

            Text(dropZoneTitle)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.ofText)
                .lineLimit(1)
                .truncationMode(.middle)

            Text(OffsendStrings.directoryCheckDropHint)
                .font(.system(size: 12))
                .foregroundColor(.ofTextSub)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
        .padding(.horizontal, OFSpacing.lg)
        .background(isDropTargeted ? Color.ofBlueDim : Color.ofBg2)
        .cornerRadius(OFRadius.lg)
        .overlay(
            RoundedRectangle(cornerRadius: OFRadius.lg)
                .stroke(isDropTargeted ? Color.ofBlue : Color.ofBorder2, style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
        )
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "shield.lefthalf.filled")
                .font(.system(size: 28))
                .foregroundColor(.ofTextMuted)

            Text(OffsendStrings.directoryCheckEmpty)
                .font(.system(size: 13))
                .foregroundColor(.ofTextSub)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .background(Color.ofBg2)
        .cornerRadius(OFRadius.md)
        .overlay(
            RoundedRectangle(cornerRadius: OFRadius.md)
                .stroke(Color.ofBorder, lineWidth: 1)
        )
    }

    private var dropZoneTitle: String {
        guard let selectedDirectory else {
            return OffsendStrings.directoryCheckDropTitle
        }
        return selectedDirectory.path
    }

    private func resultSummary(
        _ result: AIWorkspacePrivacyAuditResult,
        features: LicenseTariffFeatures,
        canAutofix: Bool
    ) -> some View {
        HStack(spacing: OFSpacing.md) {
            statusBadge(for: result.status)

            VStack(alignment: .leading, spacing: 4) {
                Text(OffsendStrings.directoryCheckSelectedDirectory(result.directoryURL.lastPathComponent))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.ofText)

                Text(result.directoryURL.path)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.ofTextMuted)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            if canFix(result) {
                if canAutofix {
                    OFButton(title: OffsendStrings.directoryCheckFixIt, variant: .primary, icon: "wand.and.stars", small: true) {
                        fix(result)
                    }
                } else {
                    OFButton(title: OffsendStrings.directoryCheckFixItPro, variant: .primary, icon: "crown.fill", small: true) {
                        Task { await coordinator.openProCheckout(prefillEmail: nil) }
                    }
                }
            }
        }
        .padding(OFSpacing.md)
        .background(statusDimColor(for: result.status))
        .cornerRadius(OFRadius.md)
        .overlay(
            RoundedRectangle(cornerRadius: OFRadius.md)
                .stroke(statusColor(for: result.status).opacity(0.35), lineWidth: 1)
        )
    }

    private func findingsSection(
        _ result: AIWorkspacePrivacyAuditResult,
        features: LicenseTariffFeatures
    ) -> some View {
        VStack(alignment: .leading, spacing: OFSpacing.md) {
            if !result.errors.isEmpty {
                findingGroup(title: OffsendStrings.directoryCheckSectionErrors, icon: "exclamationmark.triangle.fill") {
                    ForEach(result.errors) { error in
                        findingRow(title: error.message, subtitle: error.id, color: .ofRed)
                    }
                }
            }

            if !result.missingRequiredRules.isEmpty {
                findingGroup(title: OffsendStrings.directoryCheckSectionRequired, icon: "xmark.octagon.fill") {
                    ForEach(result.missingRequiredRules) { finding in
                        findingRow(title: finding.rule.title, subtitle: finding.rule.remediation, color: .ofRed)
                    }
                }
            }

            if !result.missingSensitivePatterns.isEmpty {
                findingGroup(title: OffsendStrings.directoryCheckSectionSensitivePatterns, icon: "key.fill") {
                    ForEach(result.missingSensitivePatterns) { finding in
                        findingRow(title: finding.pattern.title, subtitle: finding.pattern.remediation, color: severityColor(finding.pattern.severity))
                    }
                }
            }

            if !result.missingRecommendedRules.isEmpty {
                findingGroup(title: OffsendStrings.directoryCheckSectionRecommended, icon: "exclamationmark.circle.fill") {
                    ForEach(result.missingRecommendedRules) { finding in
                        findingRow(title: finding.rule.title, subtitle: finding.rule.remediation, color: .ofAmber)
                    }
                }
            }

            if result.errors.isEmpty,
               result.missingRequiredRules.isEmpty,
               result.missingSensitivePatterns.isEmpty,
               result.missingRecommendedRules.isEmpty {
                findingRow(
                    title: OffsendStrings.directoryCheckAllGoodTitle,
                    subtitle: OffsendStrings.directoryCheckAllGoodSubtitle,
                    color: .ofGreen
                )
            }

            if !features.workspaceAuditFull {
                proUpsellCard
            }

            if let fixMessage {
                findingRow(title: OffsendStrings.directoryCheckFixResultTitle, subtitle: fixMessage, color: .ofBlue)
            }

            if !result.foundRelativePaths.isEmpty {
                findingGroup(title: OffsendStrings.directoryCheckSectionFoundFiles, icon: "checkmark.circle.fill") {
                    ForEach(result.foundRelativePaths, id: \.self) { path in
                        findingRow(title: path, subtitle: OffsendStrings.directoryCheckFoundFileSubtitle, color: .ofGreen)
                    }
                }
            }
        }
    }

    private var proUpsellCard: some View {
        VStack(alignment: .leading, spacing: OFSpacing.sm) {
            Label(OffsendStrings.directoryCheckProUpsellTitle, systemImage: "crown.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.ofBlue)

            Text(OffsendStrings.directoryCheckProUpsellBody)
                .font(.system(size: 12))
                .foregroundColor(.ofTextSub)
                .fixedSize(horizontal: false, vertical: true)

            OFButton(title: OffsendStrings.directoryCheckProUpsellCta, variant: .outline, icon: "arrow.up.right", small: true) {
                Task { await coordinator.openProCheckout(prefillEmail: nil) }
            }
        }
        .padding(OFSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.ofBg2)
        .cornerRadius(OFRadius.md)
        .overlay(
            RoundedRectangle(cornerRadius: OFRadius.md)
                .stroke(Color.ofBorder, lineWidth: 1)
        )
    }

    private func findingGroup<Content: View>(
        title: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: OFSpacing.sm) {
            Label(title, systemImage: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.ofTextSub)

            VStack(spacing: OFSpacing.sm) {
                content()
            }
        }
    }

    private func findingRow(title: String, subtitle: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: OFSpacing.sm) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
                .padding(.top, 5)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.ofText)

                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundColor(.ofTextSub)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(OFSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.ofBg2)
        .cornerRadius(OFRadius.md)
        .overlay(
            RoundedRectangle(cornerRadius: OFRadius.md)
                .stroke(Color.ofBorder, lineWidth: 1)
        )
    }

    private func statusBadge(for status: AIWorkspacePrivacyAuditStatus) -> some View {
        Text(statusTitle(for: status))
            .font(.system(size: 12, weight: .bold))
            .foregroundColor(statusTextColor(for: status))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(statusDimColor(for: status))
            .cornerRadius(999)
    }

    private func chooseDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = OffsendStrings.directoryCheckChooseFolder

        if panel.runModal() == .OK, let url = panel.url {
            audit(directoryURL: url)
        }
    }

    private func prefillDirectoryFromPasteboard() {
        guard selectedDirectory == nil, let directoryURL = directoryURLFromPasteboard() else {
            return
        }
        audit(directoryURL: directoryURL)
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }) else {
            return false
        }

        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            guard let url = fileURL(from: item), isDirectory(url) else {
                return
            }

            DispatchQueue.main.async {
                audit(directoryURL: url)
            }
        }
        return true
    }

    private func audit(directoryURL: URL) {
        let standardizedURL = directoryURL.standardizedFileURL
        selectedDirectory = standardizedURL
        fixMessage = nil
        auditResult = auditor.audit(directoryURL: standardizedURL, configuration: auditConfiguration)
    }

    private func fix(_ result: AIWorkspacePrivacyAuditResult) {
        guard canAutofix else { return }

        let fixResult = fixer.fix(result: result, configuration: auditConfiguration)
        if fixResult.errors.isEmpty {
            fixMessage = fixSummary(fixResult)
        } else {
            fixMessage = fixResult.errors.map(\.message).joined(separator: "\n")
        }
        auditResult = auditor.audit(directoryURL: result.directoryURL, configuration: auditConfiguration)
    }

    private func canFix(_ result: AIWorkspacePrivacyAuditResult) -> Bool {
        result.errors.isEmpty && result.status != .pass
    }

    private func fixSummary(_ result: AIWorkspacePrivacyFixResult) -> String {
        if !result.didChangeFiles {
            return OffsendStrings.directoryCheckFixNoChanges
        }

        var parts: [String] = []
        if !result.createdRelativePaths.isEmpty {
            parts.append(OffsendStrings.directoryCheckFixCreated(result.createdRelativePaths.joined(separator: ", ")))
        }
        if !result.updatedRelativePaths.isEmpty {
            parts.append(OffsendStrings.directoryCheckFixUpdated(result.updatedRelativePaths.joined(separator: ", ")))
        }
        return parts.joined(separator: "\n")
    }

    private func directoryURLFromPasteboard() -> URL? {
        let pasteboard = NSPasteboard.general
        if let urls = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [NSURL],
           let directoryURL = urls.map({ $0 as URL }).first(where: { isDirectory($0) }) {
            return directoryURL
        }

        if let fileURLString = pasteboard.string(forType: .fileURL),
           let url = URL(string: fileURLString),
           url.isFileURL,
           isDirectory(url) {
            return url
        }

        if let path = pasteboard.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !path.isEmpty {
            let url = URL(fileURLWithPath: path)
            if isDirectory(url) {
                return url
            }
        }

        return nil
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

    nonisolated private func isDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    private func statusTitle(for status: AIWorkspacePrivacyAuditStatus) -> String {
        switch status {
        case .pass:
            return OffsendStrings.directoryCheckStatusPass
        case .warning:
            return OffsendStrings.directoryCheckStatusWarning
        case .fail:
            return OffsendStrings.directoryCheckStatusFail
        }
    }

    private func statusColor(for status: AIWorkspacePrivacyAuditStatus) -> Color {
        switch status {
        case .pass:
            return .ofGreen
        case .warning:
            return .ofAmber
        case .fail:
            return .ofRed
        }
    }

    private func statusTextColor(for status: AIWorkspacePrivacyAuditStatus) -> Color {
        switch status {
        case .pass:
            return .ofGreenText
        case .warning:
            return .ofAmberText
        case .fail:
            return .ofRedText
        }
    }

    private func statusDimColor(for status: AIWorkspacePrivacyAuditStatus) -> Color {
        switch status {
        case .pass:
            return .ofGreenDim
        case .warning:
            return .ofAmberDim
        case .fail:
            return .ofRedDim
        }
    }

    private func severityColor(_ severity: AIWorkspacePrivacyRuleSeverity) -> Color {
        switch severity {
        case .required:
            return .ofRed
        case .recommended:
            return .ofAmber
        case .informational:
            return .ofBlue
        }
    }
}

private struct DirectoryCheckWindowSizer: NSViewRepresentable {
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
            resizeWindow(for: nsView, animated: true)
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
