import Hummingbird
import Logging

@main
struct OffsendScanAPIApp {
    static func main() async throws {
        let config = AppConfiguration.fromEnvironment()
        let logger = Logger(label: "OffsendScanAPI")
        let app = try await ApplicationBuilder.build(config: config, logger: logger)
        try await app.runService()
    }
}
