import Foundation

public struct ShowReporter: Sendable {
    public init() {}

    public func render(_ report: ShowReport, format: CheckOutputFormat) -> String {
        switch format {
        case .text:
            return renderText(report)
        case .json:
            return renderJSON(report)
        }
    }

    private func renderText(_ report: ShowReport) -> String {
        var lines: [String] = []

        for error in report.errors {
            lines.append("! \(error)")
        }

        if report.hasErrors, !report.hasExposure {
            return lines.joined(separator: "\n")
        }

        if !report.hasExposure {
            lines.append("No sensitive files are exposed to AI tools.")
            return lines.joined(separator: "\n")
        }

        lines.append("\(report.totalExposedCount) file(s) would be sent to AI tools:")
        for group in report.groups {
            lines.append("")
            lines.append("\(group.typeTitle) [\(group.severity)]")
            for path in group.relativePaths {
                lines.append("  - \(path)")
            }
        }

        return lines.joined(separator: "\n")
    }

    private func renderJSON(_ report: ShowReport) -> String {
        struct GroupPayload: Encodable {
            let typeID: String
            let typeTitle: String
            let severity: String
            let relativePaths: [String]
        }
        struct Payload: Encodable {
            let directory: String
            let totalExposedCount: Int
            let scanIncomplete: Bool
            let groups: [GroupPayload]
            let errors: [String]
        }

        let payload = Payload(
            directory: report.directoryPath,
            totalExposedCount: report.totalExposedCount,
            scanIncomplete: report.scanIncomplete,
            groups: report.groups.map {
                GroupPayload(
                    typeID: $0.typeID,
                    typeTitle: $0.typeTitle,
                    severity: $0.severity,
                    relativePaths: $0.relativePaths
                )
            },
            errors: report.errors
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(payload),
              let json = String(data: data, encoding: .utf8) else {
            return #"{"groups":[],"totalExposedCount":0,"errors":[]}"#
        }
        return json
    }
}
