import XCTest
@testable import OffsendRuntime

final class PromptShellAuditGateTests: XCTestCase {
    func testParsesCursorAfterShellExecution() throws {
        let json = #"{"command":"cat .env","output":"TOKEN=abc","sandbox":false}"#
        let input = try PromptShellAuditGate.parse(json: json, adapter: .cursor)
        XCTAssertEqual(input.command, "cat .env")
        XCTAssertEqual(input.output, "TOKEN=abc")
        XCTAssertFalse(input.truncated)
        XCTAssertEqual(input.sandboxed, false)
    }

    func testParsesClaudePostToolUseBash() throws {
        let json = """
        {"tool_name":"Bash","tool_input":{"command":"printenv"},\
        "tool_response":{"stdout":"TOKEN=abc"}}
        """
        let input = try PromptShellAuditGate.parse(json: json, adapter: .claude)
        XCTAssertEqual(input.command, "printenv")
        XCTAssertTrue(input.output.contains("TOKEN=abc"))
    }

    func testRejectsClaudeNonBashTool() {
        let json = #"{"tool_name":"Read","tool_input":{"file_path":".env"}}"#
        XCTAssertThrowsError(try PromptShellAuditGate.parse(json: json, adapter: .claude))
    }

    func testNoFindingsWhenOutputIsClean() {
        let input = PromptShellAuditInput(command: "ls", output: "README.md")
        let decision = PromptShellAuditGate.evaluate(input: input, secretTypes: [])
        XCTAssertFalse(decision.hasFindings)
        XCTAssertEqual(decision.reason, "")
    }

    /// The gate is observational: a finding must never look like a denial or a
    /// hook crash, or the editor will start treating shell output as blockable.
    func testFindingsNeverBlockTheCommand() {
        let input = PromptShellAuditInput(command: "printenv", output: "x")
        let decision = PromptShellAuditGate.evaluate(input: input, secretTypes: ["openAIAPIKey"])
        XCTAssertTrue(decision.hasFindings)
        XCTAssertTrue(decision.reason.contains("rotate"))
        for adapter in [CheckHookAdapter.cursor, .claude] {
            let rendered = PromptShellAuditGateRenderer.render(decision: decision, adapter: adapter)
            XCTAssertEqual(rendered.exitCode, 0)
            XCTAssertEqual(rendered.stdout, "{}")
            XCTAssertFalse(rendered.stderr.isEmpty)
        }
    }

    func testTruncationIsDisclosedInReason() {
        let input = PromptShellAuditInput(command: "cat big.log", output: "x", truncated: true)
        let decision = PromptShellAuditGate.evaluate(input: input, secretTypes: ["awsAccessKeyId"])
        XCTAssertTrue(decision.reason.contains("KB of output was scanned"))
    }

    func testOversizedOutputIsBoundedAndFlagged() throws {
        let big = String(repeating: "a", count: PromptShellAuditGate.maxOutputBytes + 4_096)
        let json = try jsonLine(["command": "cat big.log", "output": big])
        let input = try PromptShellAuditGate.parse(json: json, adapter: .cursor)
        XCTAssertTrue(input.truncated)
        XCTAssertLessThanOrEqual(input.output.utf8.count, PromptShellAuditGate.maxOutputBytes)
    }

    func testLogRecordsTypesButNeverSecretValues() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("offsend-audit-\(UUID().uuidString)")
            .appendingPathComponent("shell-output-audit.log")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        ShellOutputAuditLog.append(
            ShellOutputAuditLog.Entry(
                command: "printenv OPENAI_API_KEY",
                secretTypes: ["openAIAPIKey"],
                sandboxed: false
            ),
            to: url
        )
        let contents = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(contents.contains("openAIAPIKey"))
        XCTAssertTrue(contents.contains("printenv OPENAI_API_KEY"))
        XCTAssertTrue(contents.contains("\"sandboxed\":false"))

        let summaries = ShellOutputAuditLog.recentSummaries(from: url)
        XCTAssertEqual(summaries.count, 1)
        XCTAssertEqual(summaries.first?.count, 1)
        XCTAssertEqual(summaries.first?.secretTypes, ["openAIAPIKey"])
    }

    private func jsonLine(_ object: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: object)
        return String(decoding: data, as: UTF8.self)
    }
}
