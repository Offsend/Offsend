import DetectionCore
import Foundation
import MaskingCore

public struct OffsendSealRequest: Sendable {
    public let text: String
    public let keyData: Data
    public let maxPlaintextBytes: Int
    public let disabledDetectors: Set<SensitiveEntityType>
    public let customDictionaries: [CustomDictionaryItem]

    public init(
        text: String,
        keyData: Data,
        maxPlaintextBytes: Int = SealEngine.defaultMaxPlaintextBytes,
        disabledDetectors: Set<SensitiveEntityType> = [],
        customDictionaries: [CustomDictionaryItem] = []
    ) {
        self.text = text
        self.keyData = keyData
        self.maxPlaintextBytes = maxPlaintextBytes
        self.disabledDetectors = disabledDetectors
        self.customDictionaries = customDictionaries
    }
}

/// Orchestrates seal/unseal for CLI and the macOS app.
///
/// App Safe Paste / document sanitize should prefer `seal(text:entities:keyData:)` —
/// entities already come from the app detection pipeline. Use the scan-based
/// overloads when you only have raw text (CLI).
public struct OffsendSealService: Sendable {
    private let detector: SensitiveDataDetecting
    private let context: OffsendRuntimeContext?

    public init(detector: SensitiveDataDetecting = DetectionEngine()) {
        self.detector = detector
        self.context = nil
    }

    public init(
        context: OffsendRuntimeContext,
        detector: SensitiveDataDetecting = DetectionEngine()
    ) {
        self.detector = detector
        self.context = context
    }

    /// App path: seal already-detected entities (no re-scan).
    public func seal(
        text: String,
        entities: [SensitiveEntity],
        keyData: Data,
        maxPlaintextBytes: Int = SealEngine.defaultMaxPlaintextBytes
    ) throws -> SealResult {
        let engine = try SealEngine(keyData: keyData, maxPlaintextBytes: maxPlaintextBytes)
        return try engine.seal(text: text, entities: entities)
    }

    /// Scan then seal with explicit detection options (App can pass AI-enabled options).
    public func seal(
        text: String,
        keyData: Data,
        detectionOptions: DetectionOptions,
        maxPlaintextBytes: Int = SealEngine.defaultMaxPlaintextBytes
    ) async throws -> SealResult {
        let engine = try SealEngine(keyData: keyData, maxPlaintextBytes: maxPlaintextBytes)
        let detection = await detector.scan(
            DetectionRequest(text: text, options: detectionOptions)
        )
        return try engine.seal(text: detection.scannedText, entities: detection.entities)
    }

    /// CLI convenience: derive options from `OffsendRuntimeContext` (AI off).
    public func seal(_ request: OffsendSealRequest) async throws -> SealResult {
        let detectionOptions: DetectionOptions
        if let context {
            var options = OffsendConfiguration.detectionOptions(
                context: context,
                enableAIDetection: false,
                disabledDetectors: request.disabledDetectors,
                additionalDictionaries: request.customDictionaries
            )
            options.honorInlineIgnore = true
            detectionOptions = options
        } else {
            var options = DetectionOptions(
                enabledTypes: Set(SensitiveEntityType.allCases).subtracting(request.disabledDetectors),
                customDictionaries: request.customDictionaries,
                aiDetectionEnabled: false,
                honorInlineIgnore: true
            )
            options.enabledTypes.subtract(request.disabledDetectors)
            detectionOptions = options
        }

        return try await seal(
            text: request.text,
            keyData: request.keyData,
            detectionOptions: detectionOptions,
            maxPlaintextBytes: request.maxPlaintextBytes
        )
    }

    public func unseal(text: String, keyData: Data) throws -> String {
        let engine = try SealEngine(keyData: keyData)
        return try engine.unseal(text: text)
    }
}
