import XCTest
@testable import OffsendRuntime

final class PromptShellGateTests: XCTestCase {
    func testAllowsHarmlessCommand() {
        let decision = PromptShellGate.evaluate(command: "swift build --product offsend")
        XCTAssertTrue(decision.allowed)
        XCTAssertTrue(decision.suspiciousPaths.isEmpty)
    }

    func testFlagsEnvFileRead() {
        let decision = PromptShellGate.evaluate(command: "cat .env")
        XCTAssertFalse(decision.allowed)
        XCTAssertEqual(decision.suspiciousPaths, [".env"])
        XCTAssertTrue(decision.reason.contains(".env"))
    }

    func testFlagsSSHKeyCopy() {
        let decision = PromptShellGate.evaluate(command: "cp ~/.ssh/id_rsa /tmp/key")
        XCTAssertFalse(decision.allowed)
        XCTAssertEqual(decision.suspiciousPaths, ["id_rsa"])
    }

    func testFlagsQuotedAndAssignedPaths() {
        XCTAssertFalse(PromptShellGate.evaluate(command: "less \"./server.pem\"").allowed)
        XCTAssertFalse(PromptShellGate.evaluate(command: "deploy --key-file=secrets/prod.key").allowed)
        XCTAssertFalse(PromptShellGate.evaluate(command: "KUBECONFIG=~/.kube/config kubectl get pods").allowed)
    }

    func testIgnoresFlagsAndDeduplicates() {
        let decision = PromptShellGate.evaluate(command: "cat .env .env; rm -rf build")
        XCTAssertFalse(decision.allowed)
        XCTAssertEqual(decision.suspiciousPaths, [".env"])

        XCTAssertTrue(PromptShellGate.evaluate(command: "ls -la --color=auto src").allowed)
    }

    func testExtractCommandCursorAndClaude() throws {
        let cursorJSON = #"{"command":"cat .env","cwd":"/repo"}"#
        let cursor = try PromptShellGate.evaluate(json: cursorJSON, adapter: .cursor)
        XCTAssertEqual(cursor.command, "cat .env")

        let claudeJSON = #"{"tool_input":{"command":"cat .env"}}"#
        let claude = try PromptShellGate.evaluate(json: claudeJSON, adapter: .claude)
        XCTAssertEqual(claude.command, "cat .env")
    }

    func testInvalidJSONThrows() {
        XCTAssertThrowsError(try PromptShellGate.evaluate(json: "not json", adapter: .cursor))
        XCTAssertThrowsError(try PromptShellGate.evaluate(json: "{}", adapter: .cursor))
    }

    func testCursorRendererAsksOnFindings() {
        let decision = PromptShellGate.evaluate(command: "cat .env")
        let output = PromptShellGateRenderer.render(decision: decision, adapter: .cursor)
        XCTAssertTrue(output.stdout.contains("\"permission\":\"ask\""))
        XCTAssertTrue(output.stdout.contains("user_message"))
        XCTAssertEqual(output.exitCode, 0)

        let allowed = PromptShellGateRenderer.render(
            decision: PromptShellGate.evaluate(command: "ls"),
            adapter: .cursor
        )
        XCTAssertTrue(allowed.stdout.contains("\"permission\":\"allow\""))
    }

    func testClaudeRendererAsksOnFindings() {
        let decision = PromptShellGate.evaluate(command: "cat .env")
        let output = PromptShellGateRenderer.render(decision: decision, adapter: .claude)
        XCTAssertTrue(output.stdout.contains("\"permissionDecision\":\"ask\""))
        XCTAssertEqual(output.exitCode, 0)

        let allowed = PromptShellGateRenderer.render(
            decision: PromptShellGate.evaluate(command: "ls"),
            adapter: .claude
        )
        XCTAssertEqual(allowed.stdout, "{}")
    }
}
