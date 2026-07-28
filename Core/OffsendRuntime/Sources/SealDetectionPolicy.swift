import DetectionCore
import Foundation

/// Seal is an agent-facing safety boundary, not the team's ordinary check
/// noise policy. A trusted `check.detectors.disable` must not leave fields
/// plaintext in a sealed read/MCP response.
public enum SealDetectionPolicy {
    /// Seal scans run every concrete detector regardless of check.disable.
    public static func effectiveDisabledDetectors(
        _ configured: Set<SensitiveEntityType>
    ) -> Set<SensitiveEntityType> {
        []
    }

    /// Seal all concrete detector/custom-dictionary findings. The fuzzy
    /// high-entropy rule remains excluded because it routinely matches hashes,
    /// source identifiers, and encoded data without proving sensitive content.
    public static func entitiesForSeal(
        _ entities: [SensitiveEntity]
    ) -> [SensitiveEntity] {
        entities.filter { $0.type != .highEntropyString }
    }

    public static func configuredDisabledIDs(_ raw: [String]?) -> [String] {
        (raw ?? []).sorted()
    }
}
