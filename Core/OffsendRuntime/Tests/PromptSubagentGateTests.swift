import XCTest
@testable import OffsendRuntime

final class PromptSubagentGateTests: XCTestCase {
    func testParseCursorTask() throws {
        let json = #"{"task":"Explore auth","subagent_type":"explore"}"#
        let call = try PromptSubagentGate.parse(json: json, adapter: .cursor)
        XCTAssertEqual(call.task, "Explore auth")
        XCTAssertEqual(call.subagentType, "explore")
    }

    func testRejectsNonCursorAdapter() {
        XCTAssertThrowsError(
            try PromptSubagentGate.parse(json: #"{"task":"x"}"#, adapter: .claude)
        )
    }

    func testDeniesSecretsByDefault() {
        let call = PromptSubagentGateCall(task: "use this key")
        let decision = PromptSubagentGate.evaluate(
            call: call,
            subagentsConfig: nil,
            secretTypes: ["openAIAPIKey"]
        )
        XCTAssertEqual(decision.permission, .deny)
        XCTAssertEqual(decision.code, "secrets")
    }

    func testObserveAllowsWithStderrReason() {
        let call = PromptSubagentGateCall(task: "secret task")
        let config = OffsendProjectSubagentsConfig(mode: "observe", scanTask: true)
        let decision = PromptSubagentGate.evaluate(
            call: call,
            subagentsConfig: config,
            secretTypes: ["githubToken"]
        )
        XCTAssertEqual(decision.permission, .allow)
        XCTAssertEqual(decision.code, "secrets")
    }

    func testScanTaskDisabledAllows() {
        let call = PromptSubagentGateCall(task: "anything")
        let config = OffsendProjectSubagentsConfig(mode: "deny", scanTask: false)
        let decision = PromptSubagentGate.evaluate(
            call: call,
            subagentsConfig: config,
            secretTypes: ["openAIAPIKey"]
        )
        XCTAssertTrue(decision.allowed)
    }

    func testCursorRendererDeny() {
        let decision = PromptSubagentGateDecision(
            call: PromptSubagentGateCall(task: "x"),
            permission: .deny,
            reason: "blocked",
            code: "secrets",
            secretTypes: ["jwt"]
        )
        let output = PromptSubagentGateRenderer.render(decision: decision, adapter: .cursor)
        XCTAssertTrue(output.stdout.contains("\"permission\":\"deny\""))
    }
}
