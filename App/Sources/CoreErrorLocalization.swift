import DetectionCore
import Foundation

/// Core frameworks produce English `errorDescription`s. The app maps the typed errors it
/// recognizes onto `OffsendStrings` so user-facing messages follow the app localization;
/// free-form payload messages (download/inference failures) pass through unchanged.
enum CoreErrorLocalization {
    static func message(for error: Error) -> String {
        switch error {
        case let error as AIModelRuntimeError:
            return message(for: error)
        case let error as OllamaClientError:
            return message(for: error)
        case let error as HFTokenizerError:
            return message(for: error)
        case let error as AIModelCatalogError:
            return message(for: error)
        default:
            return (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private static func message(for error: AIModelRuntimeError) -> String {
        switch error {
        case .unsupportedFormat(let format):
            return OffsendStrings.coreErrorAiRuntimeUnsupportedFormat(format.rawValue)
        case .modelNotLoaded:
            return OffsendStrings.coreErrorAiRuntimeModelNotLoaded
        case .runtimeUnavailable(let message), .inferenceFailed(let message):
            return message
        }
    }

    private static func message(for error: OllamaClientError) -> String {
        switch error {
        case .invalidEndpoint:
            return OffsendStrings.coreErrorOllamaInvalidEndpoint
        case .modelNotFound(let name):
            return OffsendStrings.coreErrorOllamaModelNotFound(name)
        case .requestFailed(let message):
            return message
        case .invalidResponse:
            return OffsendStrings.coreErrorOllamaInvalidResponse
        }
    }

    private static func message(for error: HFTokenizerError) -> String {
        switch error {
        case .unsupportedFormat:
            return OffsendStrings.coreErrorTokenizerUnsupportedFormat
        case .missingVocabulary:
            return OffsendStrings.coreErrorTokenizerMissingVocabulary
        case .fileNotFound(let name):
            return OffsendStrings.coreErrorTokenizerFileNotFound(name)
        case .byteLevelBPEUnsupported:
            return OffsendStrings.coreErrorTokenizerByteLevelBpeUnsupported
        }
    }

    private static func message(for error: AIModelCatalogError) -> String {
        switch error {
        case .invalidRepositoryReference:
            return OffsendStrings.coreErrorAiCatalogInvalidReference
        case .invalidImportReference:
            return OffsendStrings.coreErrorAiCatalogInvalidImportReference
        case .modelNotFound(let id):
            return OffsendStrings.coreErrorAiCatalogModelNotFound(id)
        case .catalogSaveFailed(let message):
            return OffsendStrings.coreErrorAiCatalogCatalogSaveFailed(message)
        case .gatedModelRequiresToken:
            return OffsendStrings.coreErrorAiCatalogGatedRequiresToken
        case .unauthorized:
            return OffsendStrings.coreErrorAiCatalogUnauthorized
        case .downloadFailed(let message),
             .importFailed(let message),
             .unsupportedFormat(let message),
             .checksumMismatch(let message),
             .incompatibleModel(let message):
            return message
        }
    }
}
