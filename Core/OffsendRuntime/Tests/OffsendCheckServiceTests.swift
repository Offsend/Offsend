import DetectionCore
import DocumentCore
import StorageCore
import XCTest
@testable import OffsendRuntime

final class OffsendCheckServiceTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testReportsUnsupportedFormatForPDFWithCLIPipeline() async throws {
        let pdfURL = root.appendingPathComponent("scan.pdf")
        try Data("%PDF-1.4".utf8).write(to: pdfURL)

        let context = OffsendRuntimeContext(settings: .default, customDictionaries: [])
        let service = OffsendCheckService(
            context: context,
            pipeline: DocumentProcessingPipeline.forCLI()
        )
        let report = await service.run(
            OffsendCheckRequest(fileURLs: [pdfURL], workingDirectory: root)
        )

        XCTAssertTrue(report.fileFindings.isEmpty)
        XCTAssertEqual(report.fileIssues.count, 1)
        XCTAssertEqual(report.fileIssues[0].relativePath, "scan.pdf")
        XCTAssertEqual(report.fileIssues[0].message, "Unsupported format (.pdf)")
        XCTAssertFalse(report.shouldFail)
    }

    func testAnalyzesPlainTextWithCLIPipeline() async throws {
        let textURL = root.appendingPathComponent("notes.txt")
        try "Contact us at leaked@example.com".write(to: textURL, atomically: true, encoding: .utf8)

        let context = OffsendRuntimeContext(settings: .default, customDictionaries: [])
        let service = OffsendCheckService(
            context: context,
            pipeline: DocumentProcessingPipeline.forCLI()
        )
        let report = await service.run(
            OffsendCheckRequest(fileURLs: [textURL], failPolicy: .block, workingDirectory: root)
        )

        XCTAssertTrue(report.fileIssues.isEmpty)
        XCTAssertFalse(report.fileFindings.isEmpty)
        XCTAssertEqual(report.fileFindings[0].relativePath, "notes.txt")
        XCTAssertEqual(report.fileFindings[0].entityType, SensitiveEntityType.email)
    }

    func testRunTextScansPromptBuffer() async {
        let context = OffsendRuntimeContext(settings: .default, customDictionaries: [])
        let service = OffsendCheckService(context: context)
        // Use a realistic AKIA-shaped key; doc sample EXAMPLE keys are filtered.
        let text = "deploy with AWS_ACCESS_KEY_ID=AKIA1234567890ABCDEF"
        let result = await service.runText(text, failPolicy: .block)

        XCTAssertFalse(result.entities.isEmpty)
        XCTAssertEqual(result.report.fileFindings.first?.relativePath, "<stdin>")
        XCTAssertTrue(result.entities.contains { $0.type == .awsAccessKeyId })
    }

    func testRunTextSeparatesRiskReportFromSecretGateEntities() async {
        let context = OffsendRuntimeContext(settings: .default, customDictionaries: [])
        let service = OffsendCheckService(context: context)

        let secret = await service.runText(
            "deploy with AWS_ACCESS_KEY_ID=AKIA1234567890ABCDEF",
            failPolicy: .block
        )
        XCTAssertFalse(secret.entities.filter(\.type.isSecret).isEmpty)
        let gate = PromptCheckAdviceBuilder.filterEntities(secret.entities, secretsOnly: true)
        XCTAssertFalse(gate.isEmpty)
        XCTAssertTrue(gate.contains { $0.type == .awsAccessKeyId })

        // Email-only: adapter secrets-only gate stays empty even if PII appears in entities.
        let emailOnly = await service.runText("ping user@example.com please", failPolicy: .block)
        let emailGate = PromptCheckAdviceBuilder.filterEntities(emailOnly.entities, secretsOnly: true)
        XCTAssertTrue(emailGate.isEmpty)
    }
}
