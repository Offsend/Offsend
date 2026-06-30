import Foundation

enum ReportHTMLRenderer {
    struct ReportContext: Sendable {
        let title: String
        let jobID: String
        let repoURL: String
        let generatedAt: String
        let score: String
        let scanComplete: Bool
        let ignoreFiles: [IgnoreFileRow]
        let patterns: [PatternRow]
        let errors: [String]

        struct IgnoreFileRow: Sendable {
            let name: String
            let label: String
            let cssClass: String
        }

        struct PatternRow: Sendable {
            let id: String
            let severity: String
            let category: String
            let count: Int
        }
    }

    static func render(
        templates: HTMLTemplateRenderer,
        jobID: String,
        repoURL: String,
        reportJSON: String,
        generatedAt: Date
    ) throws -> String {
        try templates.report(
            jobID: jobID,
            repoURL: repoURL,
            reportJSON: reportJSON,
            generatedAt: generatedAt
        )
    }

    static func makeContext(
        jobID: String,
        repoURL: String,
        reportJSON: String,
        generatedAt: Date
    ) -> ReportContext {
        let payload = decodePayload(reportJSON)
        let formatter = ISO8601DateFormatter()

        return ReportContext(
            title: "Offsend AI Privacy Report",
            jobID: jobID,
            repoURL: repoURL,
            generatedAt: formatter.string(from: generatedAt),
            score: privacyScore(from: payload),
            scanComplete: payload?.scanComplete ?? false,
            ignoreFiles: ignoreFileRows(from: payload),
            patterns: exposedPatternRows(from: payload),
            errors: payload?.errors ?? []
        )
    }

    private struct Payload: Decodable {
        let scanComplete: Bool
        let ignoreFilesPresent: [String: Bool]
        let exposedPatterns: [Pattern]
        let totals: Totals
        let errors: [String]

        struct Pattern: Decodable {
            let id: String
            let severity: String
            let category: String
            let count: Int
        }

        struct Totals: Decodable {
            let exposedFiles: Int
            let exposedPatternTypes: Int
        }
    }

    private static func decodePayload(_ json: String) -> Payload? {
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(Payload.self, from: data)
    }

    private static func privacyScore(from payload: Payload?) -> String {
        guard let payload else { return "?" }
        let exposed = payload.totals.exposedFiles
        let ignoreCount = payload.ignoreFilesPresent.values.filter { $0 }.count
        let ignoreTotal = max(payload.ignoreFilesPresent.count, 1)
        let ignoreRatio = Double(ignoreCount) / Double(ignoreTotal)
        let exposurePenalty = min(Double(exposed), 100.0)
        let raw = max(0, min(100, Int((ignoreRatio * 70) + max(0, 30 - exposurePenalty * 0.3))))
        return "\(raw)/100"
    }

    private static func ignoreFileRows(from payload: Payload?) -> [ReportContext.IgnoreFileRow] {
        guard let payload else { return [] }
        return payload.ignoreFilesPresent.keys.sorted().map { key in
            let present = payload.ignoreFilesPresent[key] == true
            return ReportContext.IgnoreFileRow(
                name: key,
                label: present ? "yes" : "missing",
                cssClass: present ? "ok" : "bad"
            )
        }
    }

    private static func exposedPatternRows(from payload: Payload?) -> [ReportContext.PatternRow] {
        guard let payload else { return [] }
        return payload.exposedPatterns.map { pattern in
            ReportContext.PatternRow(
                id: pattern.id,
                severity: pattern.severity,
                category: pattern.category,
                count: pattern.count
            )
        }
    }
}
