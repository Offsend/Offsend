import DetectionCore
import Foundation

public enum AIModelRuntimeError: Error, Equatable, Sendable {
    case unsupportedFormat(AIModelFormat)
    case modelNotLoaded
    case runtimeUnavailable(String)
    case inferenceFailed(String)
}

extension AIModelRuntimeError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .unsupportedFormat(let format):
            return "No runtime available for format: \(format.rawValue)."
        case .modelNotLoaded:
            return "AI model is not loaded."
        case .runtimeUnavailable(let message):
            return message
        case .inferenceFailed(let message):
            return message
        }
    }
}

public struct AIModelBundle: Equatable, Sendable {
    public let model: InstalledAIModel
    public let directory: URL
    public let validation: AIModelBundleValidation

    public init(model: InstalledAIModel, directory: URL, validation: AIModelBundleValidation) {
        self.model = model
        self.directory = directory
        self.validation = validation
    }
}

public protocol AIModelRunning: Sendable {
    var format: AIModelFormat { get }
    func load(bundle: AIModelBundle) async throws
    func detect(text: String, options: DetectionOptions) async throws -> [SensitiveEntity]
    func unload()
}
