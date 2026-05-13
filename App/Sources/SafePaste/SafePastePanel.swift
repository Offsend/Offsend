import AppUIKit
import AppKit
import DetectionCore
import RiskScoringCore
import SwiftUI

@MainActor
final class SafePastePanelController {
    private let popover = NSPopover()

    init(
        originalText: String,
        entities: [SensitiveEntity],
        assessment: RiskAssessment,
        wasTruncated: Bool,
        onMaskAndPaste: @escaping () -> Void,
        onCopySafeVersion: @escaping () -> Void,
        onPasteOriginal: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        let rootView = SafePastePopupView(
            originalText: originalText,
            entities: entities,
            assessment: assessment,
            wasTruncated: wasTruncated,
            close: { [weak self] action in
                self?.popover.performClose(nil)
                switch action {
                case .maskAndPaste:
                    onMaskAndPaste()
                case .copySafeVersion:
                    onCopySafeVersion()
                case .pasteOriginal:
                    onPasteOriginal()
                case .cancel:
                    onCancel()
                }
            }
        )

        popover.behavior = .transient
        popover.contentSize = NSSize(width: 380, height: 500)
        popover.contentViewController = NSHostingController(rootView: rootView)
    }

    func show(from statusItem: NSStatusItem) {
        if popover.isShown {
            popover.performClose(nil)
        }

        if let button = statusItem.button {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .maxY)
        }
    }

    func close() {
        popover.performClose(nil)
    }
}

private enum SafePastePopupAction {
    case maskAndPaste
    case copySafeVersion
    case pasteOriginal
    case cancel
}

private struct SafePastePopupView: View {
    let originalText: String
    let entities: [SensitiveEntity]
    let assessment: RiskAssessment
    let wasTruncated: Bool
    let close: (SafePastePopupAction) -> Void

    private var counts: [(SensitiveEntityType, Int)] {
        Dictionary(grouping: entities, by: \.type)
            .map { ($0.key, $0.value.count) }
            .sorted { $0.0.rawValue < $1.0.rawValue }
    }

    var body: some View {
        OFPanel(width: 380) {
            VStack(spacing: 0) {
                headerSection
                OFDivider()
                bodySection
                actionsSection
                OFDivider()
                OFPrivacyFooter(hotkey: "⌘⇧V")
            }
        }
        .animation(.easeInOut(duration: 0.2), value: assessment.score)
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(uiRisk.dimColor)
                        .frame(width: 40, height: 40)

                    riskIcon
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(title)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.ofText)

                        OFRiskBadge(risk: uiRisk)
                    }

                    Text(recommendation)
                        .font(.system(size: 12))
                        .foregroundColor(.ofTextSub)
                }

                Spacer()
            }

            OFRiskMeterBar(risk: uiRisk, score: min(assessment.score, 100))
        }
        .padding(OFSpacing.xl)
        .background(
            LinearGradient(
                colors: [uiRisk.dimColor, Color.clear],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    private var bodySection: some View {
        VStack(alignment: .leading, spacing: 0) {
            if wasTruncated {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.ofAmber)

                    Text(OffsendStrings.safePasteWarningTruncated)
                        .font(.system(size: 11))
                        .foregroundColor(.ofAmberText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, OFSpacing.xl)
                .padding(.top, OFSpacing.md)
            }

            if assessment.hasCriticalSecret {
                criticalBody
            } else {
                mediumBody
            }
        }
    }

    private var mediumBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            entityList
                .padding(OFSpacing.xl)

            OFDivider()

            maskedPreviewCard
                .padding(OFSpacing.xl)
        }
    }

    private var criticalBody: some View {
        VStack(alignment: .leading, spacing: OFSpacing.md) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "key.fill")
                    .font(.system(size: 18))
                    .foregroundColor(.ofRedText)

                VStack(alignment: .leading, spacing: 4) {
                    Text(secretTitle)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.ofRedText)

                    Text(maskedSecretValue)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.ofTextSub)
                        .lineLimit(1)

                    Text(OffsendStrings.safePasteCriticalCredentialWarning)
                        .font(.system(size: 11))
                        .foregroundColor(.ofTextSub)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(OFSpacing.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.ofRedDim)
            .cornerRadius(OFRadius.sm)

            maskedPreviewCard
        }
        .padding(OFSpacing.xl)
    }

    private var maskedPreviewCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle(OffsendStrings.safePasteSectionMaskedPreview)

            ScrollView(.vertical) {
                Text(maskedPreview)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.ofTextSub)
                    .lineSpacing(5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(10)
            }
            .frame(maxWidth: .infinity, minHeight: 72, maxHeight: 105, alignment: .topLeading)
            .background(Color.ofBg2)
            .cornerRadius(OFRadius.sm)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var entityList: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionTitle(OffsendStrings.safePasteSectionDetectedEntities)
                .padding(.bottom, 6)

            ForEach(detectedEntities) { entity in
                OFCategoryRow(entity: entity)
            }
        }
    }

    private var actionsSection: some View {
        VStack(spacing: 8) {
            OFButton(
                title: assessment.hasCriticalSecret ? OffsendStrings.safePasteActionCopySafeVersion : OffsendStrings.safePasteActionMaskAndPaste,
                variant: assessment.hasCriticalSecret ? .danger : .primary,
                icon: assessment.hasCriticalSecret ? "shield.fill" : "shield.lefthalf.filled"
            ) {
                close(assessment.hasCriticalSecret ? .copySafeVersion : .maskAndPaste)
            }
            .keyboardShortcut(.defaultAction)
            .frame(maxWidth: .infinity)

            // HStack(spacing: 8) {
                OFButton(title: OffsendStrings.safePasteActionCancel, variant: .ghost) {
                    close(.cancel)
                }

                // Spacer()

                // if !assessment.hasCriticalSecret {
                    OFButton(title: OffsendStrings.safePasteActionPasteOriginal, variant: .outline) {
                        close(.pasteOriginal)
                    }
                // }
            // }
        }
        .padding(.horizontal, OFSpacing.xl)
        .padding(.vertical, OFSpacing.md)
    }

    private var riskIcon: some View {
        Image(systemName: assessment.hasCriticalSecret ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
            .font(.system(size: 20))
            .foregroundColor(uiRisk.accentColor)
    }

    private var uiRisk: OFRiskLevel {
        assessment.hasCriticalSecret ? .critical : .medium
    }

    private var title: String {
        assessment.hasCriticalSecret ? OffsendStrings.safePasteTitleCriticalSecret : OffsendStrings.safePasteTitleSensitiveData
    }

    private var recommendation: String {
        if assessment.hasCriticalSecret {
            return OffsendStrings.safePasteRecommendationCritical
        }
        return OffsendStrings.safePasteRecommendationMask
    }

    private var detectedEntities: [OFDetectedEntity] {
        counts.map { type, count in
            OFDetectedEntity(
                icon: type.isSecret ? "key.fill" : icon(for: type),
                label: displayName(type, count: count),
                count: count,
                severity: severity(for: type)
            )
        }
    }

    private var maskedPreview: String {
        let sortedEntities = entities.sorted { $0.range.lowerBound < $1.range.lowerBound }
        var counters: [SensitiveEntityType: Int] = [:]
        var replacements: [(range: Range<String.Index>, placeholder: String)] = []

        for entity in sortedEntities {
            let nextCount = (counters[entity.type] ?? 0) + 1
            counters[entity.type] = nextCount
            replacements.append((entity.range, "{{\(entity.type.placeholderPrefix)_\(nextCount)}}"))
        }

        var output = originalText
        for replacement in replacements.reversed() {
            output.replaceSubrange(replacement.range, with: replacement.placeholder)
        }

        return output
    }

    private var secretTitle: String {
        guard let secret = entities.first(where: { $0.type.isSecret }) else {
            return OffsendStrings.safePasteSecretFound
        }
        return displayName(secret.type, count: 1)
    }

    private var maskedSecretValue: String {
        guard let secret = entities.first(where: { $0.type.isSecret }) else {
            return "••••••••••••••••"
        }

        let value = secret.value
        guard value.count > 8 else {
            return "••••••••"
        }

        return "\(value.prefix(4))••••••••••••\(value.suffix(4))"
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .kerning(0.8)
            .foregroundColor(.ofTextMuted)
    }

    private func displayName(_ type: SensitiveEntityType, count: Int) -> String {
        AppLocalization.sensitiveEntityTypeName(type, plural: count != 1)
    }

    private func icon(for type: SensitiveEntityType) -> String {
        switch type {
        case .email:
            return "envelope"
        case .phone:
            return "phone"
        case .money:
            return "dollarsign"
        case .url:
            return "link"
        case .ipAddress, .internalDomain, .customInternalDomain:
            return "network"
        case .contractId, .invoiceId, .orderId:
            return "doc.text"
        case .customClient, .customCompany, .customProject:
            return "building.2"
        default:
            return type.isSecret ? "key.fill" : "tag.fill"
        }
    }

    private func severity(for type: SensitiveEntityType) -> OFEntitySeverity {
        if type.isSecret {
            return .critical
        }

        switch type {
        case .creditCardLike, .iban:
            return .high
        case .email, .phone, .money, .url, .ipAddress:
            return .medium
        default:
            return .medium
        }
    }
}
