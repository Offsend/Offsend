import Foundation
import OffsendReportCore

struct RepositoryScanner: Sendable {
    func scan(directoryURL: URL) -> PrivacyReport {
        ScanReportService(configuration: .default).run(directoryURL: directoryURL)
    }

    func renderJSON(_ report: PrivacyReport, toolVersion: String) -> String {
        ReportReporter().renderJSON(report, toolVersion: toolVersion, generatedAt: Date())
    }
}
