import AppKit
import DetectionCore
import Foundation

enum AIModelImportFailure: Equatable, Sendable {
    case gatedRequiresToken
    case accessDenied
    case incompatibleModel(String)
    case alreadyInstalled(String)
    case invalidURL
    case invalidReference
    case modelNotFound(String)
    case downloadFailed(String)
}

enum AIModelImportAlert {
    static func present(_ failure: AIModelImportFailure) {
        let alert = NSAlert()
        alert.messageText = OffsendStrings.alertAiModelTitle
        alert.informativeText = informativeText(for: failure)
        alert.alertStyle = alertStyle(for: failure)
        alert.addButton(withTitle: OffsendStrings.alertDismiss)
        alert.runModal()
    }

    static func failure(for error: AIModelCatalogError, hasHuggingFaceToken: Bool) -> AIModelImportFailure {
        switch error {
        case .unauthorized:
            return hasHuggingFaceToken ? .accessDenied : .gatedRequiresToken
        case .gatedModelRequiresToken:
            return .gatedRequiresToken
        case .incompatibleModel(let message):
            return .incompatibleModel(message)
        case .invalidRepositoryReference, .invalidImportReference:
            return .invalidReference
        case .modelNotFound(let id):
            return .modelNotFound(id)
        case .downloadFailed(let message), .importFailed(let message):
            return downloadFailure(for: message)
        case .catalogSaveFailed(let message), .unsupportedFormat(let message), .checksumMismatch(let message):
            return .downloadFailed(message)
        }
    }

    static func statusMessage(for failure: AIModelImportFailure) -> String {
        switch failure {
        case .gatedRequiresToken:
            return OffsendStrings.statusAiModelGatedRequiresToken
        case .accessDenied:
            return OffsendStrings.statusAiModelAccessDenied
        case .incompatibleModel(let message):
            return OffsendStrings.statusAiModelIncompatible(message)
        case .alreadyInstalled(let name):
            return OffsendStrings.statusAiModelAlreadyInstalled(name)
        case .invalidURL:
            return OffsendStrings.statusAiModelInvalidURL
        case .invalidReference:
            return OffsendStrings.statusAiModelInvalidReference
        case .modelNotFound(let id):
            return OffsendStrings.statusAiModelDownloadFailed(
                OffsendStrings.alertAiModelModelNotFoundMessage(id)
            )
        case .downloadFailed(let message):
            return OffsendStrings.statusAiModelDownloadFailed(message)
        }
    }

    private static func informativeText(for failure: AIModelImportFailure) -> String {
        let message: String
        let recovery: String?

        switch failure {
        case .gatedRequiresToken:
            message = OffsendStrings.alertAiModelGatedRequiresTokenMessage
            recovery = OffsendStrings.alertAiModelGatedRequiresTokenRecovery
        case .accessDenied:
            message = OffsendStrings.alertAiModelAccessDeniedMessage
            recovery = OffsendStrings.alertAiModelAccessDeniedRecovery
        case .incompatibleModel(let detail):
            message = OffsendStrings.alertAiModelIncompatibleMessage(detail)
            recovery = OffsendStrings.alertAiModelIncompatibleRecovery
        case .alreadyInstalled(let name):
            message = OffsendStrings.alertAiModelAlreadyInstalledMessage(name)
            recovery = nil
        case .invalidURL:
            message = OffsendStrings.alertAiModelInvalidURLMessage
            recovery = OffsendStrings.alertAiModelInvalidURLRecovery
        case .invalidReference:
            message = OffsendStrings.alertAiModelInvalidReferenceMessage
            recovery = OffsendStrings.alertAiModelInvalidReferenceRecovery
        case .modelNotFound(let id):
            message = OffsendStrings.alertAiModelModelNotFoundMessage(id)
            recovery = OffsendStrings.alertAiModelModelNotFoundRecovery
        case .downloadFailed(let detail):
            message = OffsendStrings.alertAiModelDownloadFailedMessage(detail)
            recovery = OffsendStrings.alertAiModelDownloadFailedRecovery
        }

        guard let recovery, !recovery.isEmpty else { return message }
        return "\(message)\n\n\(recovery)"
    }

    private static func alertStyle(for failure: AIModelImportFailure) -> NSAlert.Style {
        switch failure {
        case .alreadyInstalled:
            return .informational
        default:
            return .warning
        }
    }

    private static func downloadFailure(for message: String) -> AIModelImportFailure {
        let lowercased = message.lowercased()
        if lowercased.contains("403") || lowercased.contains("401") {
            return .accessDenied
        }
        return .downloadFailed(message)
    }
}
