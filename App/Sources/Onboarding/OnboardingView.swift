import AppKit
import AppUIKit
import HotkeyService
import SwiftUI

private enum OnboardingStep: Int, CaseIterable {
    case welcome
    case privacy
    case hotkeys
    case permissions
    case directoryWatch
    case sample

    var label: String {
        switch self {
        case .welcome:
            return OffsendStrings.onboardingStepWelcome
        case .privacy:
            return OffsendStrings.onboardingStepPrivacy
        case .hotkeys:
            return OffsendStrings.onboardingStepHotkeys
        case .permissions:
            return OffsendStrings.onboardingStepPermissions
        case .directoryWatch:
            return OffsendStrings.onboardingStepDirectoryWatch
        case .sample:
            return OffsendStrings.onboardingStepSample
        }
    }
}

struct OnboardingView: View {
    private static let stepContentHeight: CGFloat = 320

    @EnvironmentObject private var coordinator: AppCoordinator
    @Environment(\.dismiss) private var dismiss
    @State private var currentStep: OnboardingStep = .welcome
    @State private var isStepTransitionForward = true
    @AppStorage(OFSettingsChromeAppearance.appStorageKey) private var chromeAppearanceRaw: String =
        OFSettingsChromeAppearance.auto.rawValue
    @State private var systemAppearanceRevision = 0
    @State private var accessibilityStatusRevision = 0
    @State private var safePasteHotkey = HotkeyDisplay.safePaste
    @State private var restoreHotkey = HotkeyDisplay.restorePlaceholders
    @State private var addedWatchFolderName: String?

    private let sampleText = OffsendStrings.onboardingSampleText

    private var chromeAppearance: OFSettingsChromeAppearance {
        OFSettingsChromeAppearance(rawValue: chromeAppearanceRaw) ?? .auto
    }

    private var palette: OFPalette {
        _ = systemAppearanceRevision
        return chromeAppearance.resolvedPalette()
    }

    private var isAccessibilityGranted: Bool {
        _ = accessibilityStatusRevision
        return coordinator.permissionsService.isAccessibilityTrusted
    }

    var body: some View {
        VStack(spacing: 0) {
            progressBar
                .padding(.horizontal, OFSpacing.xxl)
                .padding(.top, OFSpacing.xl)
                .padding(.bottom, OFSpacing.md)

            OFDivider()

            stepContent
                .id(currentStep)
                .frame(
                    maxWidth: .infinity,
                    minHeight: Self.stepContentHeight,
                    maxHeight: Self.stepContentHeight,
                    alignment: .topLeading
                )
                .transition(stepTransition)
                .animation(.easeInOut(duration: 0.25), value: currentStep)

            OFDivider()

            footer
        }
        .frame(width: 620)
        .background(palette.bg1)
        .environment(\.ofPalette, palette)
        .preferredColorScheme(chromeAppearance.preferredColorScheme)
        .tint(palette.blue)
        .ofRefreshOnSystemAppearanceChange($systemAppearanceRevision)
        .onChange(of: chromeAppearanceRaw) { _ in
            systemAppearanceRevision += 1
        }
        .onAppear {
            safePasteHotkey = HotkeyDisplay.safePaste
            restoreHotkey = HotkeyDisplay.restorePlaceholders
        }
        .onReceive(NotificationCenter.default.publisher(for: .keyboardShortcutDidChange)) { _ in
            safePasteHotkey = HotkeyDisplay.safePaste
            restoreHotkey = HotkeyDisplay.restorePlaceholders
        }
        .background(HiddenTitleBarWindowConfigurator(revision: currentStep.rawValue))
    }

    private var progressBar: some View {
        HStack(spacing: 0) {
            ForEach(OnboardingStep.allCases, id: \.rawValue) { step in
                HStack(spacing: 6) {
                    ZStack {
                        Circle()
                            .fill(stepCircleColor(step))
                            .frame(width: 22, height: 22)

                        if step.rawValue < currentStep.rawValue {
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.white)
                        } else {
                            Text("\(step.rawValue + 1)")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(step.rawValue <= currentStep.rawValue ? .white : .ofTextMuted)
                        }
                    }

                    Text(step.label)
                        .font(.system(size: 12, weight: step == currentStep ? .semibold : .regular))
                        .foregroundColor(step.rawValue <= currentStep.rawValue ? .ofText : .ofTextSub)
                        .opacity(step.rawValue <= currentStep.rawValue ? 1 : 0.45)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .layoutPriority(1)
                }

                if step != .sample {
                    Rectangle()
                        .fill(step.rawValue < currentStep.rawValue ? Color.ofGreen : Color.ofBorder)
                        .frame(height: 1)
                        .padding(.horizontal, 8)
                        .frame(maxWidth: .infinity)
                        .animation(.easeInOut(duration: 0.3), value: currentStep)
                }
            }
        }
    }

    private var stepContent: some View {
        Group {
            switch currentStep {
            case .welcome:
                welcome
            case .privacy:
                privacy
            case .hotkeys:
                hotkeys
            case .permissions:
                permissions
            case .directoryWatch:
                directoryWatch
            case .sample:
                sampleScenario
            }
        }
        .padding(OFSpacing.xxl)
    }

    private var footer: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                if currentStep != .welcome {
                    OFButton(title: OffsendStrings.onboardingButtonBack, variant: .ghost, icon: "chevron.left") {
                        moveBack()
                    }
                }

                Spacer()

                OFButton(
                    title: currentStep == .sample ? OffsendStrings.onboardingButtonFinish : OffsendStrings.onboardingButtonContinue,
                    variant: .primary,
                    icon: currentStep == .sample ? "checkmark" : "arrow.right"
                ) {
                    moveForward()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, OFSpacing.xxl)
            .padding(.vertical, OFSpacing.lg)

            OFPrivacyFooter(text: OffsendStrings.onboardingFooterPrivacy)
        }
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 16) {

            OffsendAsset.Images.logoFull.swiftUIImage
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(height: 28)
                .foregroundStyle(Color.ofText)

            VStack(alignment: .leading, spacing: 8) {
                Text(OffsendStrings.onboardingWelcomeTitle)
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(.ofText)

                Text(OffsendStrings.onboardingWelcomeSubtitle)
                    .font(.system(size: 14))
                    .foregroundColor(.ofTextSub)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 10) {
                featureRow(icon: "lock.fill", text: OffsendStrings.onboardingWelcomeFeatureClipboard)
                featureRow(icon: "folder.fill", text: OffsendStrings.onboardingWelcomeFeatureDirectoryCheck)
                featureRow(icon: "desktopcomputer", text: OffsendStrings.onboardingWelcomeFeatureLocal)
                featureRow(icon: "bolt.fill", text: OffsendStrings.onboardingWelcomeFeatureFast)
            }
            .padding(.top, OFSpacing.sm)
        }
    }

    private var privacy: some View {
        VStack(alignment: .leading, spacing: 16) {
            stepHeader(
                title: OffsendStrings.onboardingPrivacyTitle,
                subtitle: OffsendStrings.onboardingPrivacySubtitle
            )

            VStack(alignment: .leading, spacing: 10) {
                featureRow(icon: "clipboard", text: OffsendStrings.onboardingPrivacyFeatureClipboard)
                featureRow(icon: "lock.shield", text: OffsendStrings.onboardingPrivacyFeaturePrompt)
                featureRow(icon: "key", text: OffsendStrings.onboardingPrivacyFeatureMappings)
                featureRow(icon: "eye.slash", text: OffsendStrings.onboardingPrivacyFeatureMonitoring)
            }
        }
    }

    private var hotkeys: some View {
        VStack(alignment: .leading, spacing: 16) {
            stepHeader(
                title: OffsendStrings.onboardingHotkeysTitle,
                subtitle: OffsendStrings.onboardingHotkeysSubtitle
            )

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                hotkeyCard(key: safePasteHotkey, label: OffsendStrings.onboardingHotkeysSafePaste)
                hotkeyCard(key: restoreHotkey, label: OffsendStrings.onboardingHotkeysRestore)
                hotkeyCard(key: OffsendStrings.windowSettings, label: OffsendStrings.onboardingHotkeysSettings)
                hotkeyCard(key: OffsendStrings.onboardingHotkeysMenuBarKey, label: OffsendStrings.onboardingHotkeysMenuBar)
            }
        }
    }

    private var permissions: some View {
        VStack(alignment: .leading, spacing: 16) {
            stepHeader(
                title: OffsendStrings.onboardingPermissionsTitle,
                subtitle: OffsendStrings.onboardingPermissionsSubtitle
            )

            HStack(alignment: .top, spacing: 14) {
                iconTile(systemName: "accessibility", tint: .ofBlue, background: .ofBlueDim, size: 40)

                VStack(alignment: .leading, spacing: 8) {
                    Text(OffsendStrings.onboardingPermissionsCardTitle)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.ofText)

                    Text(OffsendStrings.onboardingPermissionsCardSubtitle)
                        .font(.system(size: 12))
                        .foregroundColor(.ofTextSub)
                        .fixedSize(horizontal: false, vertical: true)

                    accessibilityStatusMessage

                    if !isAccessibilityGranted {
                        HStack(spacing: 8) {
                            OFButton(title: OffsendStrings.onboardingPermissionsOpenSystemSettings, variant: .outline, icon: "arrow.up.right", small: true) {
                                coordinator.permissionsService.openAccessibilitySettings()
                            }

                            OFButton(title: OffsendStrings.onboardingPermissionsLater, variant: .ghost, small: true) {
                                moveForward()
                            }
                        }
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(OFSpacing.md)
            .background(Color.ofBg2)
            .cornerRadius(OFRadius.md)
            .overlay(
                RoundedRectangle(cornerRadius: OFRadius.md)
                    .stroke(Color.ofBorder, lineWidth: 1)
            )
        }
        .onAppear {
            accessibilityStatusRevision += 1
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            accessibilityStatusRevision += 1
        }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            accessibilityStatusRevision += 1
        }
    }

    private var accessibilityStatusMessage: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: isAccessibilityGranted ? "checkmark.circle.fill" : "info.circle.fill")
                .font(.system(size: 11, weight: .semibold))
                .padding(.top, 2)

            Text(
                isAccessibilityGranted
                    ? OffsendStrings.onboardingPermissionsGranted
                    : OffsendStrings.onboardingPermissionsLimitedHint
            )
            .font(.system(size: 12, weight: .medium))
            .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundColor(isAccessibilityGranted ? .ofGreenText : .ofTextSub)
    }

    private var directoryWatch: some View {
        VStack(alignment: .leading, spacing: 16) {
            stepHeader(
                title: OffsendStrings.onboardingDirectoryWatchTitle,
                subtitle: OffsendStrings.onboardingDirectoryWatchSubtitle
            )

            Text(OffsendStrings.onboardingDirectoryWatchDescription)
                .font(.system(size: 14))
                .foregroundColor(.ofTextSub)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)

            if let addedWatchFolderName {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.ofGreenText)
                        .padding(.top, 1)

                    Text(OffsendStrings.onboardingDirectoryWatchAdded(addedWatchFolderName))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.ofGreenText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(OFSpacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.ofGreenDim)
                .cornerRadius(OFRadius.md)
            } else {
                OFButton(
                    title: OffsendStrings.onboardingDirectoryWatchAddFolder,
                    variant: .outline,
                    icon: "folder.badge.plus",
                    small: true
                ) {
                    chooseMonitoredDirectory()
                }
            }

            Text(OffsendStrings.onboardingDirectoryWatchSkipHint)
                .font(.system(size: 12))
                .foregroundColor(.ofTextMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func chooseMonitoredDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = OffsendStrings.onboardingDirectoryWatchAddFolder

        guard panel.runModal() == .OK, let url = panel.url else { return }
        if coordinator.addWatchedDirectory(url: url, source: "onboarding") {
            addedWatchFolderName = url.standardizedFileURL.lastPathComponent
        }
    }

    private var sampleScenario: some View {
        VStack(alignment: .leading, spacing: 16) {
            stepHeader(
                title: OffsendStrings.onboardingSampleTitle,
                subtitle: OffsendStrings.onboardingSampleSubtitle
            )

            Text(OffsendStrings.onboardingSampleDescription)
                .font(.system(size: 14))
                .foregroundColor(.ofTextSub)
                .lineSpacing(3)

            Text(sampleText)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.ofText)
                .textSelection(.enabled)
                .padding(OFSpacing.md)
                .background(Color.ofBg2)
                .cornerRadius(OFRadius.md)
                .overlay(
                    RoundedRectangle(cornerRadius: OFRadius.md)
                        .stroke(Color.ofBorder, lineWidth: 1)
                )

            OFButton(title: OffsendStrings.onboardingSampleCopy, variant: .outline, icon: "doc.on.doc", small: true) {
                coordinator.copyOnboardingSampleToClipboard(sampleText)
            }
        }
    }

    private func stepHeader(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(.ofText)

            Text(subtitle)
                .font(.system(size: 14))
                .foregroundColor(.ofTextSub)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func featureRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(.ofBlue)
                .frame(width: 20)

            Text(text)
                .font(.system(size: 13))
                .foregroundColor(.ofTextSub)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func hotkeyCard(key: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            KbdBadge(text: key)

            Text(label)
                .font(.system(size: 11))
                .foregroundColor(.ofTextMuted)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.ofBg2)
        .cornerRadius(OFRadius.sm)
    }

    private func iconTile(
        systemName: String,
        tint: Color,
        background: Color,
        size: CGFloat = 56
    ) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: size > 40 ? 14 : 9)
                .fill(background)
                .frame(width: size, height: size)

            Image(systemName: systemName)
                .font(.system(size: size > 40 ? 26 : 16))
                .foregroundColor(tint)
        }
    }

    private func iconTile(
        icon: Image,
        tint: Color,
        background: Color,
        size: CGFloat = 56
    ) -> some View {
        let glyphSize = size > 40 ? size * 26 / 56 : size * 16 / 40

        return ZStack {
            RoundedRectangle(cornerRadius: size > 40 ? 14 : 9)
                .fill(background)
                .frame(width: size, height: size)

            icon
                .resizable()
                .renderingMode(.template)
                .aspectRatio(contentMode: .fit)
                .frame(width: glyphSize, height: glyphSize)
                .foregroundStyle(tint)
        }
    }

    private var stepTransition: AnyTransition {
        if isStepTransitionForward {
            .asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            )
        } else {
            .asymmetric(
                insertion: .move(edge: .leading).combined(with: .opacity),
                removal: .move(edge: .trailing).combined(with: .opacity)
            )
        }
    }

    private func stepCircleColor(_ step: OnboardingStep) -> Color {
        if step.rawValue < currentStep.rawValue {
            return .ofGreen
        }
        if step == currentStep {
            return .ofBlue
        }
        return .ofBg3
    }

    private func moveBack() {
        guard let previousStep = OnboardingStep(rawValue: currentStep.rawValue - 1) else {
            return
        }
        isStepTransitionForward = false
        withAnimation(.easeInOut(duration: 0.25)) {
            currentStep = previousStep
        }
    }

    private func moveForward() {
        guard currentStep != .sample else {
            coordinator.completeOnboarding()
            dismiss()
            return
        }

        guard let nextStep = OnboardingStep(rawValue: currentStep.rawValue + 1) else {
            return
        }
        isStepTransitionForward = true
        withAnimation(.easeInOut(duration: 0.25)) {
            currentStep = nextStep
        }
    }
}

private struct HiddenTitleBarWindowConfigurator: NSViewRepresentable {
    let revision: Int

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            configure(view.window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            configure(nsView.window)
        }
    }

    private func configure(_ window: NSWindow?) {
        guard let window else { return }

        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.styleMask.insert(.fullSizeContentView)
    }
}
