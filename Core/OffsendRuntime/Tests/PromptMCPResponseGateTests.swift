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
        XCTAssertEqual(call.responseShape, .object)
    }

    func testParseCursorPostToolUse() throws {
        let json = #"{"tool_name":"MCP:postgres/query","tool_output":"{\"rows\":[{\"token\":\"value\"}]}"}"#
        let call = try PromptMCPResponseGate.parse(json: json, adapter: .cursor)
        XCTAssertEqual(call.server, "postgres")
        XCTAssertEqual(call.tool, "query")
        XCTAssertTrue(call.responseText.contains("token"))
        XCTAssertTrue(call.canReplaceOutput)
        XCTAssertEqual(call.responseShape, .object)
    }

    func testParseClaudePostToolUse() throws {
        let json = #"{"tool_name":"mcp__github__get_secret","tool_response":{"token":"ghp_example"}}"#
        let call = try PromptMCPResponseGate.parse(json: json, adapter: .claude)
        XCTAssertEqual(call.server, "github")
        XCTAssertEqual(call.tool, "get_secret")
        XCTAssertTrue(call.responseText.contains("ghp_example"))
        XCTAssertEqual(call.responseShape, .object)
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
        let big = String(repeating: "a", count: PromptMCPResponseGate.maxResponseBytes + 100)
        let object: [String: Any] = ["tool_name": "mcp__fs__read", "tool_response": big]
        let data = try JSONSerialization.data(withJSONObject: object)
        let call = try PromptMCPResponseGate.parse(
            json: String(data: data, encoding: .utf8)!,
            adapter: .claude
        )
        XCTAssertTrue(call.truncated)
        XCTAssertEqual(call.responseText.utf8.count, PromptMCPResponseGate.maxResponseBytes)
    }

    func testBoundedCutsOnUTF8ByteBudgetWithoutSplittingCharacters() throws {
        // "я" is 2 UTF-8 bytes: an odd byte budget cannot split the character.
        let big = String(repeating: "я", count: PromptMCPResponseGate.maxResponseBytes / 2 + 10)
        let object: [String: Any] = ["tool_name": "mcp__fs__read", "tool_response": big]
        let data = try JSONSerialization.data(withJSONObject: object)
        let call = try PromptMCPResponseGate.parse(
            json: String(data: data, encoding: .utf8)!,
            adapter: .claude
        )
        XCTAssertTrue(call.truncated)
        XCTAssertLessThanOrEqual(call.responseText.utf8.count, PromptMCPResponseGate.maxResponseBytes)
        XCTAssertTrue(call.responseText.allSatisfy { $0 == "я" })
    }

    func testDoesNotTruncateAtLegacy50KBoundary() throws {
        let key = "AKIA1234567890ABCDEF"
        let body = String(repeating: "a", count: 55_000) + key
        let object: [String: Any] = ["tool_name": "mcp__fs__read", "tool_response": body]
        let data = try JSONSerialization.data(withJSONObject: object)
        let call = try PromptMCPResponseGate.parse(
            json: String(data: data, encoding: .utf8)!,
            adapter: .claude
        )
        XCTAssertFalse(call.truncated)
        XCTAssertTrue(call.responseText.hasSuffix(key))
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

    func testSealModeWithoutKeyExplainsWithhold() {
        let call = PromptMCPResponseCall(
            server: "s",
            tool: "t",
            responseText: "x",
            canReplaceOutput: true
        )
        let decision = PromptMCPResponseGate.evaluate(
            call: call,
            mcpConfig: OffsendProjectMCPConfig(responses: "seal"),
            secretTypes: ["awsAccessKeyID"]
        )
        XCTAssertEqual(decision.mode, .seal)
        XCTAssertNil(decision.sealedOutput)
        XCTAssertTrue(decision.reason.contains("Sealing unavailable"))
        XCTAssertTrue(decision.reason.contains("withheld"))
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

    func testSealModeTruncatedWithoutPrefixFindingIsStillUnsafe() {
        let call = PromptMCPResponseCall(
            server: "s",
            tool: "t",
            responseText: String(repeating: "a", count: 10),
            truncated: true,
            canReplaceOutput: true
        )
        let decision = PromptMCPResponseGate.evaluate(
            call: call,
            mcpConfig: OffsendProjectMCPConfig(responses: "seal")
        )
        XCTAssertTrue(decision.hasFindings)
        XCTAssertTrue(decision.reason.contains("withheld"))
    }

    // MARK: - Renderer: Cursor

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

    func testCursorPostToolUseSealReplacesMCPOutput() throws {
        let call = PromptMCPResponseCall(
            server: "unknown",
            tool: "MCP:github/get",
            responseText: #"{"token":"plaintext"}"#,
            canReplaceOutput: true,
            responseShape: .object
        )
        let decision = PromptMCPResponseGate.evaluate(
            call: call,
            mcpConfig: OffsendProjectMCPConfig(responses: "seal"),
            secretTypes: ["githubToken"],
            sealedOutput: #"{"token":"{{GITHUB_TOKEN:v1.AbC-d_9}}"}"#,
            sealedCount: 1
        )
        let output = PromptMCPResponseGateRenderer.render(decision: decision, adapter: .cursor)
        let root = try json(output.stdout)
        let replacement = try XCTUnwrap(root["updated_mcp_tool_output"] as? [String: Any])
        XCTAssertEqual(replacement["token"] as? String, "{{GITHUB_TOKEN:v1.AbC-d_9}}")
        XCTAssertNotNil(root["additional_context"])
    }

    func testCursorSealModeWithoutKeyWithholdsOutput() throws {
        let call = PromptMCPResponseCall(
            server: "github",
            tool: "get",
            responseText: #"{"token":"plaintext"}"#,
            canReplaceOutput: true,
            responseShape: .object
        )
        let decision = PromptMCPResponseGate.evaluate(
            call: call,
            mcpConfig: OffsendProjectMCPConfig(responses: "seal"),
            secretTypes: ["githubToken"]
        )
        let output = PromptMCPResponseGateRenderer.render(decision: decision, adapter: .cursor)
        let root = try json(output.stdout)
        let replacement = try XCTUnwrap(root["updated_mcp_tool_output"] as? [String: Any])
        XCTAssertNotNil(replacement["error"])
        XCTAssertFalse(output.stdout.contains("plaintext"))
    }

    func testCursorTruncatedSealWithholdsOutputWithoutPrefixFinding() throws {
        let call = PromptMCPResponseCall(
            server: "unknown",
            tool: "MCP:github/get",
            responseText: "safe prefix",
            truncated: true,
            canReplaceOutput: true
        )
        let decision = PromptMCPResponseGate.evaluate(
            call: call,
            mcpConfig: OffsendProjectMCPConfig(responses: "seal")
        )
        let output = PromptMCPResponseGateRenderer.render(decision: decision, adapter: .cursor)
        let root = try json(output.stdout)
        XCTAssertNotNil(root["updated_mcp_tool_output"])
    }

    func testOversizedHookInputUsesSafeReplacementShapes() throws {
        let cursor = PromptMCPResponseGateRenderer.renderLimitExceeded(adapter: .cursor)
        XCTAssertNotNil(try json(cursor.stdout)["updated_mcp_tool_output"])

        let claude = PromptMCPResponseGateRenderer.renderLimitExceeded(adapter: .claude)
        let hook = try XCTUnwrap(
            try json(claude.stdout)["hookSpecificOutput"] as? [String: Any]
        )
        XCTAssertNotNil(hook["updatedToolOutput"])
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

    /// `updatedToolOutput` is documented as a string; a structured value risks
    /// a silently ignored replacement, so sealed JSON is sent as text.
    func testClaudeSealModeEmitsStructuredResponseAsSealedJSONText() throws {
        let sealed = #"{"content":[{"text":"{{GITHUB_TOKEN:v1.AbC-d_9}}","type":"text"},{"type":"image","source":{"id":"img-1"}}],"meta":{"count":2}}"#
        let call = PromptMCPResponseCall(
            server: "github",
            tool: "get",
            responseText: #"{"content":[]}"#,
            responseShape: .object
        )
        let decision = PromptMCPResponseGate.evaluate(
            call: call,
            mcpConfig: OffsendProjectMCPConfig(responses: "seal"),
            secretTypes: ["githubToken"],
            sealedOutput: sealed,
            sealedCount: 1
        )
        let output = PromptMCPResponseGateRenderer.render(decision: decision, adapter: .claude)
        let root = try json(output.stdout)
        let hook = try XCTUnwrap(root["hookSpecificOutput"] as? [String: Any])
        XCTAssertEqual(hook["updatedToolOutput"] as? String, sealed)
        XCTAssertEqual(hook["updatedMCPToolOutput"] as? String, sealed)
    }

    func testClaudeSealModeEmitsArrayResponseAsSealedJSONText() throws {
        let sealed = #"["{{GITHUB_TOKEN:v1.AbC-d_9}}"]"#
        let call = PromptMCPResponseCall(
            server: "github",
            tool: "get",
            responseText: #"["plaintext"]"#,
            responseShape: .array
        )
        let decision = PromptMCPResponseGate.evaluate(
            call: call,
            mcpConfig: OffsendProjectMCPConfig(responses: "seal"),
            secretTypes: ["githubToken"],
            sealedOutput: sealed,
            sealedCount: 1
        )
        let output = PromptMCPResponseGateRenderer.render(decision: decision, adapter: .claude)
        let root = try json(output.stdout)
        let hook = try XCTUnwrap(root["hookSpecificOutput"] as? [String: Any])
        XCTAssertEqual(hook["updatedToolOutput"] as? String, sealed)
    }

    func testCursorSealFailureWithholdsOutput() throws {
        let call = PromptMCPResponseCall(
            server: "github",
            tool: "get",
            responseText: #"{"token":"plaintext"}"#,
            canReplaceOutput: true,
            responseShape: .object
        )
        let decision = PromptMCPResponseGate.evaluate(
            call: call,
            mcpConfig: OffsendProjectMCPConfig(responses: "seal"),
            secretTypes: ["githubToken"],
            sealFailed: true
        )
        XCTAssertTrue(decision.reason.contains("Sealing failed"))
        let output = PromptMCPResponseGateRenderer.render(decision: decision, adapter: .cursor)
        let root = try json(output.stdout)
        let replacement = try XCTUnwrap(root["updated_mcp_tool_output"] as? [String: Any])
        XCTAssertNotNil(replacement["error"])
        XCTAssertFalse(output.stdout.contains("plaintext"))
    }

    func testClaudeSealFailureWithholdsOutput() throws {
        let call = PromptMCPResponseCall(
            server: "github",
            tool: "get",
            responseText: #"{"token":"plaintext"}"#,
            canReplaceOutput: true
        )
        let decision = PromptMCPResponseGate.evaluate(
            call: call,
            mcpConfig: OffsendProjectMCPConfig(responses: "seal"),
            secretTypes: ["githubToken"],
            sealFailed: true
        )
        let output = PromptMCPResponseGateRenderer.render(decision: decision, adapter: .claude)
        let root = try json(output.stdout)
        let hook = try XCTUnwrap(root["hookSpecificOutput"] as? [String: Any])
        let replacement = try XCTUnwrap(hook["updatedToolOutput"] as? String)
        XCTAssertTrue(replacement.contains("withheld"))
        XCTAssertEqual(hook["updatedMCPToolOutput"] as? String, replacement)
        XCTAssertFalse(output.stdout.contains("plaintext"))
    }

    func testParseClaudePostToolUseCanReplaceOutput() throws {
        let json = #"{"tool_name":"mcp__fs__read","tool_response":"body"}"#
        let call = try PromptMCPResponseGate.parse(json: json, adapter: .claude)
        XCTAssertTrue(call.canReplaceOutput)
    }

    func testClaudeSealModeWithoutKeyWithholdsOutput() throws {
        let call = PromptMCPResponseCall(
            server: "s",
            tool: "t",
            responseText: "plaintext",
            canReplaceOutput: true
        )
        let decision = PromptMCPResponseGate.evaluate(
            call: call,
            mcpConfig: OffsendProjectMCPConfig(responses: "seal"),
            secretTypes: ["apiKeyGeneric"]
        )
        let output = PromptMCPResponseGateRenderer.render(decision: decision, adapter: .claude)
        let root = try json(output.stdout)
        let hook = try XCTUnwrap(root["hookSpecificOutput"] as? [String: Any])
        XCTAssertNotNil(hook["updatedToolOutput"])
        XCTAssertNotNil(hook["updatedMCPToolOutput"])
        XCTAssertNotNil(hook["additionalContext"])
        XCTAssertFalse(output.stdout.contains("plaintext"))
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
