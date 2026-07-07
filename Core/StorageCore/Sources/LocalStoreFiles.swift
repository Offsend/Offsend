import Foundation

struct LocalStoreFiles {
    let directory: URL

    var settings: URL { directory.appendingPathComponent("settings.json") }
    var customDictionaries: URL { directory.appendingPathComponent("custom_dictionaries.json") }
    var mappings: URL { directory.appendingPathComponent("mappings.sqlite.json") }
    var events: URL { directory.appendingPathComponent("local_events.json") }
    var license: URL { directory.appendingPathComponent("license.json") }
}

struct LocalStoreJSONCodec {
    let encoder: JSONEncoder
    let decoder: JSONDecoder

    init() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    func load<T: Decodable>(_ type: T.Type, from url: URL) throws -> T? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try decoder.decode(T.self, from: Data(contentsOf: url))
    }

    func save<T: Encodable>(_ value: T, to url: URL) throws {
        let data = try encoder.encode(value)
        try data.write(to: url, options: [.atomic])
    }
}
