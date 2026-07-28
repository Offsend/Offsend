import XCTest
@testable import OffsendRuntime

final class PromptGrepGateTests: XCTestCase {
    func testSealModeDeniesAllGrep() {
        let call = PromptGrepGateCall(path: nil, pattern: "API_KEY")
        let decision = PromptGrepGate.evaluate(
            call: call,
            readConfig: OffsendProjectReadConfig(onSecret: "seal"),
            secretTypes: []
        )
        XCTAssertEqual(decision.permission, .deny)
        XCTAssertEqual(decision.code, "seal_no_grep_rewrite")
    }

    func testBlockModeAllowsWhenNoSecrets() {
        let call = PromptGrepGateCall(path: "/tmp/readme.md", pattern: "foo")
        let decision = PromptGrepGate.evaluate(
            call: call,
            readConfig: OffsendProjectReadConfig(onSecret: "block"),
            secretTypes: []
        )
        XCTAssertEqual(decision.permission, .allow)
    }

    func testBlockModeDeniesFileWithSecrets() {
        let call = PromptGrepGateCall(path: "/tmp/index.js", pattern: "sk-")
        let decision = PromptGrepGate.evaluate(
            call: call,
            readConfig: nil,
            secretTypes: ["openAIAPIKey"]
        )
        XCTAssertEqual(decision.permission, .deny)
        XCTAssertEqual(decision.code, "secrets")
    }

    func testParseNestedToolInputPath() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("index.js")
        try "const x = 1\n".write(to: file, atomically: true, encoding: .utf8)
        let json = """
        {"tool_name":"Grep","cwd":"\(dir.path)","tool_input":{"pattern":"x","path":"index.js"}}
        """
        let call = try PromptGrepGate.parse(json: json, adapter: .cursor)
        XCTAssertEqual(call.path, file.path)
        XCTAssertEqual(call.pattern, "x")
    }

    func testCursorRendererDenyIncludesAgentMessage() {
        let decision = PromptGrepGateDecision(
            call: PromptGrepGateCall(),
            permission: .deny,
            reason: "blocked",
            agentMessage: "use Read",
            code: "seal_no_grep_rewrite"
        )
        let output = PromptGrepGateRenderer.render(decision: decision, adapter: .cursor)
        XCTAssertTrue(output.stdout.contains("\"permission\":\"deny\""))
        XCTAssertTrue(output.stdout.contains("agent_message"))
    }
}
