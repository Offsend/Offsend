import DetectionCore
import Foundation

extension Sequence where Element == SensitiveEntity {
    /// First entity per distinct `value`, preserving encounter order.
    func uniqueByValue() -> [(entityID: UUID, value: String)] {
        var seen: Set<String> = []
        var result: [(entityID: UUID, value: String)] = []
        for entity in self where seen.insert(entity.value).inserted {
            result.append((entity.id, entity.value))
        }
        return result
    }
}
