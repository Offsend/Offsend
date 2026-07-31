import Foundation

struct CheckScanResult: Sendable, Equatable {
    let json: String
    let hasErrors: Bool
    let errorIDs: [String]

    init(json: String) {
        self.json = json
        if let data = json.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let errors = object["errors"] as? [String]
        {
            self.errorIDs = errors
            self.hasErrors = !errors.isEmpty
        } else {
            self.errorIDs = []
            self.hasErrors = false
        }
    }
}

struct RepositoryScanner: Sendable {
    func scan(directoryURL: URL, toolVersion: String) throws -> CheckScanResult {
        let json = try OffsendCheckBridge.checkReportJSON(
            directory: directoryURL,
            toolVersion: toolVersion
        )
        return CheckScanResult(json: json)
    }
}
