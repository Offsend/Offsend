import XCTest
@testable import OffsendRuntime

final class CheckHookResponseRendererTests: XCTestCase {
    func testPolicyDriftFailsClosedForPromptAndToolGates() {
        let cursorPrompt = CheckHookResponseRenderer.failClosed(
            adapter: .cursor,
            reason: "policy changed",
            kind: .promptSubmit
        )
        XCTAssertTrue(cursorPrompt.stdout.contains("\"continue\":false"))

        let claudeRead = CheckHookResponseRenderer.failClosed(
            adapter: .claude,
            reason: "policy changed",
            kind: .readGate
        )
        XCTAssertTrue(claudeRead.stdout.contains("\"permissionDecision\":\"deny\""))

        let cursorWrite = CheckHookResponseRenderer.failClosed(
            adapter: .cursor,
            reason: "policy changed",
            kind: .writeGate
        )
        XCTAssertTrue(cursorWrite.stdout.contains("\"permission\":\"deny\""))
    }

    func testPolicyDriftWithholdsMCPResponse() {
        let cursor = CheckHookResponseRenderer.failClosed(
            adapter: .cursor,
            reason: "policy changed",
            kind: .mcpResponseGate
        )
        XCTAssertTrue(cursor.stdout.contains("updated_mcp_tool_output"))

        let claude = CheckHookResponseRenderer.failClosed(
            adapter: .claude,
            reason: "policy changed",
            kind: .mcpResponseGate
        )
        XCTAssertTrue(claude.stdout.contains("updatedToolOutput"))
    }
}
