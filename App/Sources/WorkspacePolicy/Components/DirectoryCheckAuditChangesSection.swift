import AppUIKit
import SwiftUI
import WorkspacePolicyCore

struct DirectoryCheckAuditChangesSection: View {
    let delta: AIWorkspacePrivacyAuditDelta

    var body: some View {
        VStack(alignment: .leading, spacing: OFSpacing.sm) {
            Text(OffsendStrings.directoryCheckChangesTitle)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.ofText)

            if delta.previousStatus != delta.currentStatus {
                Text(
                    OffsendStrings.directoryCheckChangesStatus(
                        DirectoryCheckPresentation.statusTitle(for: delta.previousStatus),
                        DirectoryCheckPresentation.statusTitle(for: delta.currentStatus)
                    )
                )
                .font(.system(size: 12))
                .foregroundColor(.ofTextSub)
            }

            ForEach(delta.newlyMissingRules, id: \.rule.id) { finding in
                Text(OffsendStrings.directoryCheckChangesNewlyMissingRule(finding.rule.title))
                    .font(.system(size: 12))
                    .foregroundColor(.ofTextSub)
            }

            ForEach(delta.newlySatisfiedRules, id: \.rule.id) { finding in
                Text(OffsendStrings.directoryCheckChangesNewlySatisfiedRule(finding.rule.title))
                    .font(.system(size: 12))
                    .foregroundColor(.ofTextSub)
            }

            ForEach(delta.newlyMissingPatterns, id: \.pattern.id) { finding in
                Text(OffsendStrings.directoryCheckChangesNewlyMissingPattern(finding.pattern.title))
                    .font(.system(size: 12))
                    .foregroundColor(.ofTextSub)
            }

            ForEach(delta.newlySatisfiedPatterns, id: \.pattern.id) { finding in
                Text(OffsendStrings.directoryCheckChangesNewlySatisfiedPattern(finding.pattern.title))
                    .font(.system(size: 12))
                    .foregroundColor(.ofTextSub)
            }

            ForEach(delta.removedMatchedPaths, id: \.self) { path in
                Text(OffsendStrings.directoryCheckChangesRemovedPath(path))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.ofTextSub)
            }

            ForEach(delta.addedMatchedPaths, id: \.self) { path in
                Text(OffsendStrings.directoryCheckChangesAddedPath(path))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.ofTextSub)
            }

            ForEach(delta.addedExposedRelativePaths, id: \.self) { path in
                Text(OffsendStrings.directoryCheckChangesAddedExposedPath(path))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.ofTextSub)
            }

            ForEach(delta.removedExposedRelativePaths, id: \.self) { path in
                Text(OffsendStrings.directoryCheckChangesRemovedExposedPath(path))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.ofTextSub)
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
}
