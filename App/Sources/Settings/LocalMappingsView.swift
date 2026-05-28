import AppUIKit
import HotkeyService
import StorageCore
import SwiftUI

struct LocalMappingsView: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @State private var restoreHotkey = HotkeyDisplay.restorePlaceholders

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, OFSpacing.xxl)
                .padding(.top, OFSpacing.xl)
                .padding(.bottom, OFSpacing.md)

            OFDivider()

            ScrollView {
                VStack(alignment: .leading, spacing: OFSpacing.lg) {
                    Text(OffsendStrings.localMappingsDescription)
                        .font(.system(size: 14))
                        .foregroundColor(.ofTextSub)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)

                    OFMappingInfoRow(restoreHotkey: restoreHotkey)

                    if coordinator.mappingSummaries.isEmpty {
                        emptyState
                    } else {
                        VStack(spacing: OFSpacing.sm) {
                            ForEach(coordinator.mappingSummaries) { summary in
                                mappingCard(summary)
                            }
                        }
                    }

                    if !coordinator.lastStatusMessage.isEmpty {
                        Text(coordinator.lastStatusMessage)
                            .font(.system(size: 11))
                            .foregroundColor(.ofTextMuted)
                    }
                }
                .padding(OFSpacing.xxl)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(minWidth: 520, minHeight: 380)
        .background(Color.ofBg1)
        .onAppear {
            restoreHotkey = HotkeyDisplay.restorePlaceholders
            try? coordinator.refreshMappingSummaries()
        }
        .onReceive(NotificationCenter.default.publisher(for: .keyboardShortcutDidChange)) { _ in
            restoreHotkey = HotkeyDisplay.restorePlaceholders
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.ofBlueDim)
                    .frame(width: 44, height: 44)

                Image(systemName: "key.horizontal.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.ofBlue)
            }

            Text(OffsendStrings.localMappingsTitle)
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(.ofText)

            Spacer()

            HStack(spacing: 8) {
                OFButton(title: OffsendStrings.localMappingsRefresh, variant: .outline, icon: "arrow.clockwise", small: true) {
                    try? coordinator.refreshMappingSummaries()
                }

                OFButton(title: OffsendStrings.localMappingsClearAll, variant: .danger, icon: "trash", small: true) {
                    coordinator.clearAllMappings()
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "tray")
                .font(.system(size: 28))
                .foregroundColor(.ofTextMuted)

            Text(String(localized: String.LocalizationValue("localMappings.empty")))
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

    private func mappingCard(_ summary: StoredMappingSummary) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(summary.id.uuidString)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.ofText)
                .textSelection(.enabled)

            VStack(alignment: .leading, spacing: 4) {
                Text(OffsendStrings.localMappingsPlaceholderCount(summary.placeholderCount))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.ofTextSub)

                Text(expirationText(summary.expiresAt))
                    .font(.system(size: 11))
                    .foregroundColor(.ofTextMuted)
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

    private func expirationText(_ date: Date?) -> String {
        guard let date else { return OffsendStrings.localMappingsNoExpiration }
        return OffsendStrings.localMappingsExpires(date.formatted(date: .abbreviated, time: .shortened))
    }
}
