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

    func testFlagsAdditionalCredentialPaths() {
        XCTAssertFalse(PromptShellGate.evaluate(command: "cat config/master.key").allowed)
        XCTAssertFalse(PromptShellGate.evaluate(command: "less _netrc").allowed)
        XCTAssertFalse(PromptShellGate.evaluate(command: "cp secring.gpg /tmp/").allowed)
        XCTAssertFalse(PromptShellGate.evaluate(command: "cat .git-credentials").allowed)
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

    func testAsksOnOffsendUnseal() {
        let direct = PromptShellGate.evaluate(command: "offsend unseal --key-name work < sealed.txt")
        XCTAssertFalse(direct.allowed)
        XCTAssertEqual(direct.suspiciousPaths, ["offsend unseal"])
        XCTAssertTrue(direct.reason.contains("unseal"))

        let viaPath = PromptShellGate.evaluate(command: "/usr/local/bin/offsend unseal file.txt")
        XCTAssertFalse(viaPath.allowed)

        let piped = PromptShellGate.evaluate(command: "cat sealed.txt | offsend unseal")
        XCTAssertFalse(piped.allowed)
    }

    func testDoesNotFlagUnrelatedUnsealMentions() {
        // `unseal` without the offsend binary, and offsend without unseal.
        XCTAssertTrue(PromptShellGate.evaluate(command: "vault operator unseal").allowed)
        XCTAssertTrue(PromptShellGate.evaluate(command: "offsend check README.md").allowed)
        XCTAssertTrue(PromptShellGate.evaluate(command: "offsend seal notes.txt").allowed)
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

    func testFlagsSymlinkToSensitiveTargetViaCwd() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("offsend-shell-gate-symlink-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let env = root.appendingPathComponent(".env")
        let link = root.appendingPathComponent("notes.txt")
        try "SECRET=1\n".write(to: env, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: env)

        let decision = PromptShellGate.evaluate(command: "cat notes.txt", cwd: root.path)
        XCTAssertFalse(decision.allowed)
        XCTAssertEqual(decision.suspiciousPaths, [".env"])

        let json = #"{"command":"cat notes.txt","cwd":"\#(root.path)"}"#
        let fromJSON = try PromptShellGate.evaluate(json: json, adapter: .cursor)
        XCTAssertFalse(fromJSON.allowed)
        XCTAssertEqual(fromJSON.suspiciousPaths, [".env"])
    }
}
