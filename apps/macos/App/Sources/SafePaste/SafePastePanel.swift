import AppUIKit
import AppKit
import DetectionCore
import HotkeyService
import RiskScoringCore
import SwiftUI

@MainActor
final class SafePastePanelController: NSObject, NSPopoverDelegate {
    private let popover = NSPopover()
    private var onClose: ((SafePastePanelController) -> Void)?

    init(
        originalText: String,
        entities: [SensitiveEntity],
        assessment: RiskAssessment,
        wasTruncated: Bool,
        onMaskAndPaste: @escaping ([SensitiveEntity]) -> Void,
        onCopySafeVersion: @escaping ([SensitiveEntity]) -> Void,
        onPasteOriginal: @escaping () -> Void,
        onCancel: @escaping () -> Void,
        onClose: @escaping (SafePastePanelController) -> Void
    ) {
        self.onClose = onClose
        super.init()
        let rootView = SafePastePopupView(
            originalText: originalText,
            entities: entities,
            assessment: assessment,
            wasTruncated: wasTruncated,
            close: { [weak self] action in
                self?.popover.performClose(nil)
                switch action {
                case .maskAndPaste(let enabledEntities):
                    onMaskAndPaste(enabledEntities)
                case .copySafeVersion(let enabledEntities):
                    onCopySafeVersion(enabledEntities)
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
        popover.delegate = self
    }

    func popoverDidClose(_ notification: Notification) {
        onClose?(self)
        onClose = nil
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
    case maskAndPaste([SensitiveEntity])
    case copySafeVersion([SensitiveEntity])
    case pasteOriginal
    case cancel
}

private struct SafePastePopupView: View {
    let originalText: String
    let entities: [SensitiveEntity]
    let assessment: RiskAssessment
    let wasTruncated: Bool
    let close: (SafePastePopupAction) -> Void

    @State private var safePasteHotkey = HotkeyDisplay.safePaste
    @State private var maskedTypes: Set<SensitiveEntityType>

    init(
        originalText: String,
        entities: [SensitiveEntity],
        assessment: RiskAssessment,
        wasTruncated: Bool,
        close: @escaping (SafePastePopupAction) -> Void
    ) {
        self.originalText = originalText
        self.entities = entities
        self.assessment = assessment
        self.wasTruncated = wasTruncated
        self.close = close
        _maskedTypes = State(initialValue: Set(entities.map(\.type)))
    }

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
                OFPrivacyFooter(hotkey: safePasteHotkey)
            }
            .frame(maxWidth: .infinity)
        }
        .onAppear {
            safePasteHotkey = HotkeyDisplay.safePaste
        }
        .onReceive(NotificationCenter.default.publisher(for: .keyboardShortcutDidChange)) { _ in
            safePasteHotkey = HotkeyDisplay.safePaste
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

            entityList

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

            ForEach(counts, id: \.0) { type, count in
                OFCategoryRow(
                    entity: OFDetectedEntity(
                        icon: type.isSecret ? "key.fill" : icon(for: type),
                        label: displayName(type, count: count),
                        count: count,
                        severity: severity(for: type),
                        values: previewValues(for: type)
                    ),
                    isOn: binding(for: type)
                )
            }
        }
    }

    private var actionsSection: some View {
        VStack(spacing: 8) {
            OFButton(
                title: primaryActionTitle,
                variant: .primary,
                icon: primaryActionIcon,
                fillsWidth: true
            ) {
                close(assessment.hasCriticalSecret ? .copySafeVersion(enabledEntities) : .maskAndPaste(enabledEntities))
            }
            .keyboardShortcut(.defaultAction)

            HStack(spacing: 8) {
                OFButton(title: OffsendStrings.safePasteActionCancel, variant: .ghost, fillsWidth: true) {
                    close(.cancel)
                }

                if !assessment.hasCriticalSecret {
                    OFButton(title: OffsendStrings.safePasteActionPasteOriginal, variant: .outline, fillsWidth: true) {
                        close(.pasteOriginal)
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity)
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

    private func binding(for type: SensitiveEntityType) -> Binding<Bool> {
        Binding(
            get: { maskedTypes.contains(type) },
            set: { isOn in
                if isOn {
                    maskedTypes.insert(type)
                } else {
                    maskedTypes.remove(type)
                }
            }
        )
    }

    private var enabledEntities: [SensitiveEntity] {
        entities.filter { maskedTypes.contains($0.type) }
    }

    private var maskedPreview: String {
        let sortedEntities = enabledEntities.sorted { $0.range.lowerBound < $1.range.lowerBound }
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

    private var allTypesMasked: Bool {
        maskedTypes == Set(entities.map(\.type))
    }

    private var primaryActionTitle: String {
        if assessment.hasCriticalSecret {
            return allTypesMasked ? OffsendStrings.safePasteActionCopySafeVersion : OffsendStrings.safePasteActionCopyEditedVersion
        }
        return OffsendStrings.safePasteActionMaskAndPaste
    }

    private var primaryActionIcon: String {
        if assessment.hasCriticalSecret {
            return allTypesMasked ? "shield.fill" : "square.and.pencil"
        }
        return "shield.lefthalf.filled"
    }

    private func previewValues(for type: SensitiveEntityType) -> [String] {
        entities
            .filter { $0.type == type }
            .map { previewValue(for: $0) }
    }

    private func previewValue(for entity: SensitiveEntity) -> String {
        guard entity.type.isSecret else {
            return entity.value
        }

        let value = entity.value
        guard value.count > 8 else {
            return String(repeating: "•", count: max(value.count, 4))
        }

        return "\(value.prefix(4))••••\(value.suffix(4))"
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
