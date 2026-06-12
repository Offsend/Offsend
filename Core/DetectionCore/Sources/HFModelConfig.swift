import Foundation

public struct HFModelConfig: Equatable, Sendable {
    public let id2label: [Int: String]
    public let maxPositionEmbeddings: Int

    public init(id2label: [Int: String], maxPositionEmbeddings: Int = 512) {
        self.id2label = id2label
        self.maxPositionEmbeddings = maxPositionEmbeddings
    }

    public static func load(from directory: URL) -> HFModelConfig? {
        let configURL = directory.appendingPathComponent("config.json")
        guard FileManager.default.fileExists(atPath: configURL.path),
              let data = try? Data(contentsOf: configURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        var id2label: [Int: String] = [:]
        if let raw = json["id2label"] as? [String: String] {
            for (key, value) in raw {
                if let id = Int(key) {
                    id2label[id] = value
                }
            }
        }

        let maxLength = json["max_position_embeddings"] as? Int ?? 512
        guard !id2label.isEmpty else { return nil }
        return HFModelConfig(id2label: id2label, maxPositionEmbeddings: maxLength)
    }
}
