import Foundation

enum DetectionDebugLogger {
    static func logScanStart(
        characterCount: Int,
        wasTruncated: Bool,
        aiEnabled: Bool,
        selectedAIModelID: String?
    ) {
        #if DEBUG
        debugLogScanStart(
            characterCount: characterCount,
            wasTruncated: wasTruncated,
            aiEnabled: aiEnabled,
            selectedAIModelID: selectedAIModelID
        )
        #endif
    }

    static func logPhase(_ phase: String, entities: [SensitiveEntity], in text: String) {
        #if DEBUG
        debugLogPhase(phase, entities: entities, in: text)
        #endif
    }

    static func logAIDetectionError(_ message: String) {
        #if DEBUG
        debugLogAIDetectionError(message)
        #endif
    }

    static func logFilteredOut(_ removed: [SensitiveEntity], in text: String) {
        #if DEBUG
        debugLogFilteredOut(removed, in: text)
        #endif
    }
}

#if DEBUG
#if canImport(os)
import os

private enum DetectionDebugLogging {
    static let logger = Logger(subsystem: "io.offsend.detection", category: "DetectionEngine")

    static func logScanStart(
        characterCount: Int,
        wasTruncated: Bool,
        aiEnabled: Bool,
        selectedAIModelID: String?
    ) {
        let model = selectedAIModelID ?? "none"
        logger.debug(
            "scan started chars=\(characterCount, privacy: .public) truncated=\(wasTruncated, privacy: .public) ai=\(aiEnabled, privacy: .public) model=\(model, privacy: .public)"
        )
    }

    static func logPhase(_ phase: String, entities: [SensitiveEntity], in text: String) {
        guard !entities.isEmpty else {
            logger.debug("[\(phase, privacy: .public)] no matches")
            return
        }

        for entity in entities {
            let (start, end) = utf16Offsets(for: entity.range, in: text)
            logger.debug(
                """
                [\(phase, privacy: .public)] source=\(entity.source.rawValue, privacy: .public) \
                type=\(entity.type.rawValue, privacy: .public) range=\(start, privacy: .public)..<\(end, privacy: .public) \
                confidence=\(entity.confidence, privacy: .public) value=\(displayValue(entity), privacy: .public)
                """
            )
        }

        let summary = Dictionary(grouping: entities, by: \.source)
            .map { source, items in "\(source.rawValue)=\(items.count)" }
            .sorted()
            .joined(separator: ", ")
        logger.debug("[\(phase, privacy: .public)] summary: \(summary, privacy: .public)")
    }

    static func logAIDetectionError(_ message: String) {
        logger.error("ai detection failed: \(message, privacy: .public)")
    }

    static func logFilteredOut(_ removed: [SensitiveEntity], in text: String) {
        guard !removed.isEmpty else { return }
        logger.debug("false-positive filter removed \(removed.count, privacy: .public) entities")
        for entity in removed {
            let (start, end) = utf16Offsets(for: entity.range, in: text)
            logger.debug(
                """
                [filtered] source=\(entity.source.rawValue, privacy: .public) \
                type=\(entity.type.rawValue, privacy: .public) range=\(start, privacy: .public)..<\(end, privacy: .public) \
                value=\(displayValue(entity), privacy: .public)
                """
            )
        }
    }

    private static func utf16Offsets(for range: Range<String.Index>, in text: String) -> (Int, Int) {
        let start = text.utf16.distance(from: text.utf16.startIndex, to: range.lowerBound)
        let end = text.utf16.distance(from: text.utf16.startIndex, to: range.upperBound)
        return (start, end)
    }

    private static func displayValue(_ entity: SensitiveEntity) -> String {
        let value = entity.value
        if entity.type.isSecret {
            let prefix = value.prefix(4)
            return prefix.isEmpty ? "<secret>" : "\(prefix)…"
        }
        if value.count > 80 {
            return String(value.prefix(80)) + "…"
        }
        return value
    }
}

private func debugLogScanStart(
    characterCount: Int,
    wasTruncated: Bool,
    aiEnabled: Bool,
    selectedAIModelID: String?
) {
    DetectionDebugLogging.logScanStart(
        characterCount: characterCount,
        wasTruncated: wasTruncated,
        aiEnabled: aiEnabled,
        selectedAIModelID: selectedAIModelID
    )
}

private func debugLogPhase(_ phase: String, entities: [SensitiveEntity], in text: String) {
    DetectionDebugLogging.logPhase(phase, entities: entities, in: text)
}

private func debugLogAIDetectionError(_ message: String) {
    DetectionDebugLogging.logAIDetectionError(message)
}

private func debugLogFilteredOut(_ removed: [SensitiveEntity], in text: String) {
    DetectionDebugLogging.logFilteredOut(removed, in: text)
}
#else
private func debugLogScanStart(
    characterCount: Int,
    wasTruncated: Bool,
    aiEnabled: Bool,
    selectedAIModelID: String?
) {}

private func debugLogPhase(_ phase: String, entities: [SensitiveEntity], in text: String) {}

private func debugLogAIDetectionError(_ message: String) {}

private func debugLogFilteredOut(_ removed: [SensitiveEntity], in text: String) {}
#endif
#endif
