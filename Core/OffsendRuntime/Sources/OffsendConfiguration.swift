import DetectionCore
import DocumentCore
import Foundation
import MaskingCore
import StorageCore
import WorkspacePolicyCore

public enum OffsendConfiguration {
    public static func detectionOptions(
        context: OffsendRuntimeContext,
        enableAIDetection: Bool,
        disabledDetectors: Set<SensitiveEntityType> = [],
        maximumLength: Int = 50_000
    ) -> DetectionOptions {
        let aiEnabled = enableAIDetection
            && context.settings.aiDetectionEnabled
            && context.settings.selectedAIModelID != nil

        var enabledTypes = context.settings.enabledDetectors
        enabledTypes.subtract(disabledDetectors)

        return DetectionOptions(
            enabledTypes: enabledTypes,
            customDictionaries: context.tariffFeatures.customDictionaries ? context.customDictionaries : [],
            maximumLength: maximumLength,
            aiDetectionEnabled: aiEnabled,
            selectedAIModelID: context.settings.selectedAIModelID
        )
    }

    public static func documentProcessingOptions(
        context: OffsendRuntimeContext,
        enableAIDetection: Bool = false,
        disabledDetectors: Set<SensitiveEntityType> = []
    ) -> DocumentProcessingOptions {
        DocumentProcessingOptions(
            detection: detectionOptions(
                context: context,
                enableAIDetection: enableAIDetection,
                disabledDetectors: disabledDetectors
            ),
            mappingTTL: MappingTTL.effective(
                context.settings.mappingTTL,
                extendedTTLAllowed: context.isProEntitlementActive && context.tariffFeatures.safePasteUnlimited
            ),
            maximumFileByteCount: DocumentProcessingLimits.maximumFileByteCount(
                isPro: context.isProEntitlementActive
            )
        )
    }

    public static func directoryCheckConfiguration(context: OffsendRuntimeContext) -> AIWorkspacePrivacyAuditConfiguration {
        DirectoryCheckConfigurationResolver.resolve(
            DirectoryCheckConfigurationInput(
                workspaceAuditFull: context.tariffFeatures.workspaceAuditFull,
                disabledRuleIDs: context.settings.directoryCheckDisabledRuleIDs,
                extraSkippedDirectories: context.settings.directoryCheckExtraSkippedDirectories,
                customIgnoreTemplate: context.settings.directoryCheckCustomIgnoreTemplate
            )
        )
    }
}
