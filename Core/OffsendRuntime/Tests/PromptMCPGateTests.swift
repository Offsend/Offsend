import XCTest
@testable import OffsendRuntime

final class PromptMCPGateTests: XCTestCase {
    func testParseCursorCall() throws {
        let json = """
        {"server":"github","tool_name":"search","tool_input":"{\\"path\\":\\"README.md\\"}","cwd":"/repo"}
        """
        let call = try PromptMCPGate.parse(json: json, adapter: .cursor)
        XCTAssertEqual(call.server, "github")
        XCTAssertEqual(call.tool, "search")
        XCTAssertTrue(call.toolInput.contains("README.md"))
    }

    func testParseCursorUsesCommandAsServerFallback() throws {
        let json = #"{"command":"filesystem","tool_name":"read_file","tool_input":{}}"#
        let call = try PromptMCPGate.parse(json: json, adapter: .cursor)
        XCTAssertEqual(call.server, "filesystem")
    }

    func testParseClaudeMCPToolName() throws {
        let json = #"{"tool_name":"mcp__github__list_issues","tool_input":{"repo":"acme/app"}}"#
        let call = try PromptMCPGate.parse(json: json, adapter: .claude)
        XCTAssertEqual(call.server, "github")
        XCTAssertEqual(call.tool, "list_issues")
        XCTAssertTrue(
            call.toolInput.contains("acme/app") || call.toolInput.contains("acme\\/app"),
            "toolInput=\(call.toolInput)"
        )
    }

    func testRejectsNonMCPClaudeTool() {
        let json = #"{"tool_name":"Bash","tool_input":{"command":"ls"}}"#
        XCTAssertThrowsError(try PromptMCPGate.parse(json: json, adapter: .claude))
    }

    func testAllowlistDeniesUnknownServer() {
        let call = PromptMCPGateCall(server: "filesystem", tool: "read", toolInput: "{}")
        let config = OffsendProjectMCPConfig(mode: "deny", allow: ["github"], deny: ["*"])
        let decision = PromptMCPGate.evaluate(call: call, mcpConfig: config)
        XCTAssertEqual(decision.permission, .deny)
        XCTAssertEqual(decision.code, "policy")
    }

    func testNonEmptyAllowActsAsAllowlistWithoutDenyStar() {
        let config = OffsendProjectMCPConfig(mode: "deny", allow: ["github"])

        let unknown = PromptMCPGateCall(server: "filesystem", tool: "read", toolInput: "{}")
        let denied = PromptMCPGate.evaluate(call: unknown, mcpConfig: config)
        XCTAssertEqual(denied.permission, .deny)
        XCTAssertEqual(denied.code, "policy")

        let listed = PromptMCPGateCall(server: "github", tool: "search", toolInput: "{}")
        let allowed = PromptMCPGate.evaluate(call: listed, mcpConfig: config)
        XCTAssertEqual(allowed.permission, .allow)
    }

    func testDenylistBlocksListedServer() {
        let call = PromptMCPGateCall(server: "postgres", tool: "query", toolInput: "{}")
        let config = OffsendProjectMCPConfig(mode: "ask", deny: ["postgres"])
        let decision = PromptMCPGate.evaluate(call: call, mcpConfig: config)
        XCTAssertEqual(decision.permission, .ask)
        XCTAssertEqual(decision.code, "policy")
    }

    func testObserveModeAllowsThroughWithFinding() {
        let call = PromptMCPGateCall(server: "fs", tool: "read", toolInput: "cat .env")
        let config = OffsendProjectMCPConfig(mode: "observe")
        let decision = PromptMCPGate.evaluate(call: call, mcpConfig: config)
        XCTAssertEqual(decision.permission, .allow)
        XCTAssertEqual(decision.code, "sensitive_path")
        XCTAssertEqual(decision.suspiciousPaths, [".env"])
    }

    func testSensitivePathInToolInputAsksByDefault() {
        let call = PromptMCPGateCall(server: "github", tool: "read", toolInput: #"{"path":".env"}"#)
        let decision = PromptMCPGate.evaluate(call: call, mcpConfig: nil)
        XCTAssertEqual(decision.permission, .ask)
        XCTAssertEqual(decision.code, "sensitive_path")
        XCTAssertTrue(decision.reason.contains("fuel"))
    }

    func testFlagsMasterKeyAndGitCredentialsInArgs() {
        let master = PromptMCPGateCall(
            server: "fs",
            tool: "read",
            toolInput: #"{"path":"config/master.key"}"#
        )
        XCTAssertEqual(PromptMCPGate.evaluate(call: master).code, "sensitive_path")

        let gitCreds = PromptMCPGateCall(
            server: "fs",
            tool: "read",
            toolInput: ".git-credentials"
        )
        XCTAssertEqual(PromptMCPGate.evaluate(call: gitCreds).code, "sensitive_path")
    }

    func testSecretTypesDenyInDenyMode() {
        let call = PromptMCPGateCall(server: "linear", tool: "create", toolInput: "token=sk-test")
        let config = OffsendProjectMCPConfig(mode: "deny")
        let decision = PromptMCPGate.evaluate(
            call: call,
            mcpConfig: config,
            secretTypes: ["openAIAPIKey"]
        )
        XCTAssertEqual(decision.permission, .deny)
        XCTAssertEqual(decision.code, "secrets")
    }

    func testCursorRendererDenyAndAsk() {
        let call = PromptMCPGateCall(server: "x", tool: "y", toolInput: ".env")
        let deny = PromptMCPGateDecision(
            call: call,
            permission: .deny,
            reason: "blocked",
            code: "policy"
        )
        let denyOut = PromptMCPGateRenderer.render(decision: deny, adapter: .cursor)
        XCTAssertTrue(denyOut.stdout.contains("\"permission\":\"deny\""))

        let ask = PromptMCPGateDecision(
            call: call,
            permission: .ask,
            reason: "confirm",
            code: "sensitive_path",
            suspiciousPaths: [".env"]
        )
        let askOut = PromptMCPGateRenderer.render(decision: ask, adapter: .cursor)
        XCTAssertTrue(askOut.stdout.contains("\"permission\":\"ask\""))
    }

    func testClaudeRendererPermissionDecision() {
        let call = PromptMCPGateCall(server: "github", tool: "search", toolInput: "{}")
        let decision = PromptMCPGateDecision(
            call: call,
            permission: .deny,
            reason: "denied",
            code: "policy"
        )
        let output = PromptMCPGateRenderer.render(decision: decision, adapter: .claude)
        XCTAssertTrue(output.stdout.contains("\"permissionDecision\":\"deny\""))
        XCTAssertTrue(output.stdout.contains("PreToolUse"))
    }
}
