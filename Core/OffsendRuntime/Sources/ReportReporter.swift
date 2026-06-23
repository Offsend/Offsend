import Foundation

/// Serializes a `PrivacyReport` to the anonymized JSON consumed by the weekly
/// statistics pipeline. `toolVersion` and `generatedAt` are environment facts
/// injected by the caller so the report model itself stays deterministic.
public struct ReportReporter: Sendable {
    /// Bump when the JSON shape changes incompatibly.
    public static let schemaVersion = 1

    public init() {}

    public func renderJSON(_ report: PrivacyReport, toolVersion: String, generatedAt: Date) -> String {
        struct PatternPayload: Encodable {
            let id: String
            let severity: String
            let category: String
            let count: Int
        }
        struct Totals: Encodable {
            let exposedFiles: Int
            let exposedPatternTypes: Int
        }
        struct Payload: Encodable {
            let schemaVersion: Int
            let rulesetVersion: String
            let toolVersion: String
            let generatedAt: String
            let scanComplete: Bool
            let ignoreFilesPresent: [String: Bool]
            let exposedPatterns: [PatternPayload]
            let totals: Totals
            let errors: [String]
        }

        let ignoreFilesPresent = Dictionary(
            report.ignoreFiles.map { ($0.ruleID, $0.present) },
            uniquingKeysWith: { first, _ in first }
        )
        let payload = Payload(
            schemaVersion: Self.schemaVersion,
            rulesetVersion: report.rulesetVersion,
            toolVersion: toolVersion,
            generatedAt: ISO8601DateFormatter().string(from: generatedAt),
            scanComplete: report.scanComplete,
            ignoreFilesPresent: ignoreFilesPresent,
            exposedPatterns: report.exposedPatterns.map {
                PatternPayload(id: $0.patternID, severity: $0.severity, category: $0.category, count: $0.count)
            },
            totals: Totals(
                exposedFiles: report.totalExposedFiles,
                exposedPatternTypes: report.exposedPatterns.count
            ),
            errors: report.errorIDs
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(payload),
              let json = String(data: data, encoding: .utf8) else {
            return #"{"schemaVersion":\#(Self.schemaVersion),"exposedPatterns":[],"errors":[]}"#
        }
        return json
    }
}
