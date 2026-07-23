import XCTest
@testable import OffsendRuntime

final class PromptMCPResponseGateTests: XCTestCase {
    // MARK: - Parsing

    func testParseCursorAfterMCPExecution() throws {
        let json = """
        {"tool_name":"query","command":"postgres","result_json":"{\\"rows\\":[{\\"password\\":\\"hunter2\\"}]}"}
        """
        let call = try PromptMCPResponseGate.parse(json: json, adapter: .cursor)
        XCTAssertEqual(call.server, "postgres")
        XCTAssertEqual(call.tool, "query")
        XCTAssertTrue(call.responseText.contains("hunter2"))
        XCTAssertFalse(call.truncated)
    }

    func testParseCursorStructuredResultJSON() throws {
        let json = #"{"tool_name":"read","result_json":{"content":"value"}}"#
        let call = try PromptMCPResponseGate.parse(json: json, adapter: .cursor)
        XCTAssertTrue(call.responseText.contains("value"))
    }

    func testParseClaudePostToolUse() throws {
        let json = #"{"tool_name":"mcp__github__get_secret","tool_response":{"token":"ghp_example"}}"#
        let call = try PromptMCPResponseGate.parse(json: json, adapter: .claude)
        XCTAssertEqual(call.server, "github")
        XCTAssertEqual(call.tool, "get_secret")
        XCTAssertTrue(call.responseText.contains("ghp_example"))
    }

    func testParseClaudeStringToolResponse() throws {
        let json = #"{"tool_name":"mcp__fs__read","tool_response":"plain text body"}"#
        let call = try PromptMCPResponseGate.parse(json: json, adapter: .claude)
        XCTAssertEqual(call.responseText, "plain text body")
    }

    func testRejectsNonMCPClaudeTool() {
        let json = #"{"tool_name":"Bash","tool_response":"output"}"#
        XCTAssertThrowsError(try PromptMCPResponseGate.parse(json: json, adapter: .claude))
    }

    func testTruncatesOversizedResponse() throws {
        let big = String(repeating: "a", count: PromptMCPResponseGate.maxResponseCharacters + 100)
        let object: [String: Any] = ["tool_name": "mcp__fs__read", "tool_response": big]
        let data = try JSONSerialization.data(withJSONObject: object)
        let call = try PromptMCPResponseGate.parse(
            json: String(data: data, encoding: .utf8)!,
            adapter: .claude
        )
        XCTAssertTrue(call.truncated)
        XCTAssertEqual(call.responseText.count, PromptMCPResponseGate.maxResponseCharacters)
    }

    // MARK: - Evaluate

    func testNoFindingsProducesEmptyDecision() {
        let call = PromptMCPResponseCall(server: "github", tool: "list", responseText: "ok")
        let decision = PromptMCPResponseGate.evaluate(call: call, mcpConfig: nil)
        XCTAssertFalse(decision.hasFindings)
        XCTAssertEqual(decision.mode, .observe)
        XCTAssertEqual(decision.reason, "")
    }

    func testDefaultModeIsObserve() {
        let call = PromptMCPResponseCall(server: "s", tool: "t", responseText: "x")
        let decision = PromptMCPResponseGate.evaluate(
            call: call,
            mcpConfig: OffsendProjectMCPConfig(),
            secretTypes: ["apiKeyGeneric"]
        )
        XCTAssertEqual(decision.mode, .observe)
        XCTAssertTrue(decision.reason.contains("apiKeyGeneric"))
    }

    func testSealModeWithoutKeyExplainsFallback() {
        let call = PromptMCPResponseCall(server: "s", tool: "t", responseText: "x")
        let decision = PromptMCPResponseGate.evaluate(
            call: call,
            mcpConfig: OffsendProjectMCPConfig(responses: "seal"),
            secretTypes: ["awsAccessKeyID"]
        )
        XCTAssertEqual(decision.mode, .seal)
        XCTAssertNil(decision.sealedOutput)
        XCTAssertTrue(decision.reason.contains("Sealing unavailable"))
    }

    func testSealModeTruncatedExplainsFallback() {
        let call = PromptMCPResponseCall(server: "s", tool: "t", responseText: "x", truncated: true)
        let decision = PromptMCPResponseGate.evaluate(
            call: call,
            mcpConfig: OffsendProjectMCPConfig(responses: "seal"),
            secretTypes: ["awsAccessKeyID"]
        )
        XCTAssertNil(decision.sealedOutput)
        XCTAssertTrue(decision.reason.contains("too large"))
    }

    // MARK: - Renderer: Cursor (observe-only)

    func testCursorRendererNeverEmitsPermissions() throws {
        let call = PromptMCPResponseCall(server: "s", tool: "t", responseText: "x")
        let decision = PromptMCPResponseGate.evaluate(
            call: call,
            mcpConfig: OffsendProjectMCPConfig(responses: "seal"),
            secretTypes: ["apiKeyGeneric"]
        )
        let output = PromptMCPResponseGateRenderer.render(decision: decision, adapter: .cursor)
        XCTAssertEqual(output.exitCode, 0)
        XCTAssertEqual(output.stdout, "{}")
        XCTAssertTrue(output.stderr.contains("apiKeyGeneric"))
    }

    func testCursorRendererSilentWhenClean() {
        let call = PromptMCPResponseCall(server: "s", tool: "t", responseText: "ok")
        let decision = PromptMCPResponseGate.evaluate(call: call)
        let output = PromptMCPResponseGateRenderer.render(decision: decision, adapter: .cursor)
        XCTAssertEqual(output.stdout, "{}")
        XCTAssertEqual(output.stderr, "")
    }

    // MARK: - Renderer: Claude PostToolUse

    func testClaudeWarnModeEmitsAdditionalContext() throws {
        let call = PromptMCPResponseCall(server: "github", tool: "get", responseText: "x")
        let decision = PromptMCPResponseGate.evaluate(
            call: call,
            mcpConfig: OffsendProjectMCPConfig(responses: "warn"),
            secretTypes: ["githubToken"]
        )
        let output = PromptMCPResponseGateRenderer.render(decision: decision, adapter: .claude)
        let root = try json(output.stdout)
        let hook = try XCTUnwrap(root["hookSpecificOutput"] as? [String: Any])
        XCTAssertEqual(hook["hookEventName"] as? String, "PostToolUse")
        XCTAssertNil(hook["updatedToolOutput"])
        let context = try XCTUnwrap(hook["additionalContext"] as? String)
        XCTAssertTrue(context.contains("githubToken"))
    }

    func testClaudeSealModeEmitsUpdatedToolOutputWithLegacyAlias() throws {
        let sealed = "token: {{GITHUB_TOKEN:v1.AbC-d_9}}\nline \"with quotes\""
        let call = PromptMCPResponseCall(server: "github", tool: "get", responseText: "x")
        let decision = PromptMCPResponseGate.evaluate(
            call: call,
            mcpConfig: OffsendProjectMCPConfig(responses: "seal"),
            secretTypes: ["githubToken"],
            sealedOutput: sealed,
            sealedCount: 1
        )
        let output = PromptMCPResponseGateRenderer.render(decision: decision, adapter: .claude)
        // JSON-in-JSON: sealed text with quotes/newlines must survive round-trip.
        let root = try json(output.stdout)
        let hook = try XCTUnwrap(root["hookSpecificOutput"] as? [String: Any])
        XCTAssertEqual(hook["updatedToolOutput"] as? String, sealed)
        XCTAssertEqual(hook["updatedMCPToolOutput"] as? String, sealed)
        let context = try XCTUnwrap(hook["additionalContext"] as? String)
        XCTAssertTrue(context.contains("offsend unseal"))
    }

    func testClaudeSealModeWithoutSealedOutputFallsBackToWarn() throws {
        let call = PromptMCPResponseCall(server: "s", tool: "t", responseText: "x")
        let decision = PromptMCPResponseGate.evaluate(
            call: call,
            mcpConfig: OffsendProjectMCPConfig(responses: "seal"),
            secretTypes: ["apiKeyGeneric"]
        )
        let output = PromptMCPResponseGateRenderer.render(decision: decision, adapter: .claude)
        let root = try json(output.stdout)
        let hook = try XCTUnwrap(root["hookSpecificOutput"] as? [String: Any])
        XCTAssertNil(hook["updatedToolOutput"])
        XCTAssertNotNil(hook["additionalContext"])
    }

    func testClaudeObserveModeEmitsEmptyObject() {
        let call = PromptMCPResponseCall(server: "s", tool: "t", responseText: "x")
        let decision = PromptMCPResponseGate.evaluate(
            call: call,
            mcpConfig: nil,
            secretTypes: ["apiKeyGeneric"]
        )
        let output = PromptMCPResponseGateRenderer.render(decision: decision, adapter: .claude)
        XCTAssertEqual(output.stdout, "{}")
        XCTAssertFalse(output.stderr.isEmpty)
    }

    private func json(_ string: String) throws -> [String: Any] {
        try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(string.utf8)) as? [String: Any]
        )
    }
}
