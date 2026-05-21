import AppUIKit
import SwiftUI

private enum OnboardingStep: Int, CaseIterable {
    case welcome
    case privacy
    case hotkeys
    case permissions
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
        case .sample:
            return OffsendStrings.onboardingStepSample
        }
    }
}

struct OnboardingView: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @Environment(\.dismiss) private var dismiss
    @State private var currentStep: OnboardingStep = .welcome
    @AppStorage(OFSettingsChromeAppearance.appStorageKey) private var chromeAppearanceRaw: String =
        OFSettingsChromeAppearance.auto.rawValue
    @State private var systemAppearanceRevision = 0

    private let sampleText = OffsendStrings.onboardingSampleText

    private var chromeAppearance: OFSettingsChromeAppearance {
        OFSettingsChromeAppearance(rawValue: chromeAppearanceRaw) ?? .auto
    }

    private var palette: OFPalette {
        _ = systemAppearanceRevision
        return chromeAppearance.resolvedPalette()
    }

    var body: some View {
        VStack(spacing: 0) {
            progressBar
                .padding(.horizontal, OFSpacing.xxl)
                .padding(.top, OFSpacing.xl)
                .padding(.bottom, OFSpacing.md)

            OFDivider()

            stepContent
                .frame(maxWidth: .infinity, minHeight: 290, alignment: .topLeading)
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))
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
                hotkeyCard(key: "⌘⇧V", label: OffsendStrings.onboardingHotkeysSafePaste)
                hotkeyCard(key: "⌘⇧R", label: OffsendStrings.onboardingHotkeysRestore)
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

                    HStack(spacing: 8) {
                        OFButton(title: OffsendStrings.onboardingPermissionsOpenSystemSettings, variant: .outline, icon: "arrow.up.right", small: true) {
                            coordinator.permissionsService.openAccessibilitySettings()
                        }

                        OFButton(title: OffsendStrings.onboardingPermissionsLater, variant: .ghost, small: true) {}
                    }
                }

                Spacer()
            }
            .padding(OFSpacing.md)
            .background(Color.ofBg2)
            .cornerRadius(OFRadius.md)
            .overlay(
                RoundedRectangle(cornerRadius: OFRadius.md)
                    .stroke(Color.ofBorder, lineWidth: 1)
            )
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
        withAnimation { currentStep = previousStep }
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
        withAnimation { currentStep = nextStep }
    }
}
