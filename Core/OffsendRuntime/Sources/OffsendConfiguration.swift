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
        additionalDictionaries: [CustomDictionaryItem] = [],
        maximumLength: Int = 50_000
    ) -> DetectionOptions {
        let aiEnabled = enableAIDetection
            && context.settings.aiDetectionEnabled
            && context.settings.selectedAIModelID != nil

        var enabledTypes = context.settings.enabledDetectors
        enabledTypes.subtract(disabledDetectors)

        return DetectionOptions(
            enabledTypes: enabledTypes,
            customDictionaries: context.customDictionaries + additionalDictionaries,
            maximumLength: maximumLength,
            aiDetectionEnabled: aiEnabled,
            selectedAIModelID: context.settings.selectedAIModelID
        )
    }

    public static func documentProcessingOptions(
        context: OffsendRuntimeContext,
        enableAIDetection: Bool = false,
        disabledDetectors: Set<SensitiveEntityType> = [],
        additionalDictionaries: [CustomDictionaryItem] = []
    ) -> DocumentProcessingOptions {
        DocumentProcessingOptions(
            detection: detectionOptions(
                context: context,
                enableAIDetection: enableAIDetection,
                disabledDetectors: disabledDetectors,
                additionalDictionaries: additionalDictionaries
            ),
            mappingTTL: context.settings.mappingTTL,
            maximumFileByteCount: .max
        )
    }

    public static func directoryCheckConfiguration(context: OffsendRuntimeContext) -> AIWorkspacePrivacyAuditConfiguration {
        DirectoryCheckConfigurationResolver.resolve(
            DirectoryCheckConfigurationInput(
                disabledRuleIDs: context.settings.directoryCheckDisabledRuleIDs,
                extraSkippedDirectories: context.settings.directoryCheckExtraSkippedDirectories,
                customIgnoreTemplate: context.settings.directoryCheckCustomIgnoreTemplate
            )
        )
    }
}
