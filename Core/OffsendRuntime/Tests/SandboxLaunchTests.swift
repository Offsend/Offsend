import XCTest
@testable import OffsendRuntime

final class SandboxLaunchTests: XCTestCase {
    func testClaudeWithoutSandboxLaunchesBareBinary() throws {
        let invocation = try SandboxLaunch.invocation(
            target: .claude,
            sandboxEnabled: false,
            nonoAvailable: true,
            agentArguments: ["-p", "hi"]
        )

        XCTAssertEqual(invocation.program, "claude")
        XCTAssertEqual(invocation.arguments, ["-p", "hi"])
        XCTAssertFalse(invocation.usesNono)
        XCTAssertNil(invocation.mechanism)
        XCTAssertEqual(invocation.display, "claude -p hi")
    }

    func testClaudeWithSandboxAndNonoWraps() throws {
        let invocation = try SandboxLaunch.invocation(
            target: .claude,
            sandboxEnabled: true,
            nonoAvailable: true
        )

        XCTAssertEqual(invocation.program, "nono")
        XCTAssertEqual(
            invocation.arguments,
            [
                "run",
                "--profile", "./.offsend/nono/offsend-claude.json",
                "--allow-cwd",
                "--",
                "claude",
            ]
        )
        XCTAssertTrue(invocation.usesNono)
        XCTAssertEqual(invocation.mechanism, .nono)
        XCTAssertEqual(invocation.profileRelativePath, ".offsend/nono/offsend-claude.json")
    }

    func testClaudeWithSandboxWithoutNonoUsesBareBinary() throws {
        let invocation = try SandboxLaunch.invocation(
            target: .claude,
            sandboxEnabled: true,
            nonoAvailable: false
        )

        XCTAssertEqual(invocation.program, "claude")
        XCTAssertEqual(invocation.arguments, [])
        XCTAssertFalse(invocation.usesNono)
        XCTAssertEqual(invocation.mechanism, .claudeNative)
    }

    func testCodexWithNonoWraps() throws {
        let invocation = try SandboxLaunch.invocation(
            target: .codex,
            sandboxEnabled: true,
            nonoAvailable: true,
            agentArguments: ["exec", "ls"]
        )

        XCTAssertEqual(invocation.program, "nono")
        XCTAssertTrue(invocation.arguments.contains("codex"))
        XCTAssertEqual(invocation.arguments.suffix(2).map { String($0) }, ["exec", "ls"])
        XCTAssertEqual(invocation.profileRelativePath, ".offsend/nono/offsend-codex.json")
    }

    func testCursorNeverUsesNono() throws {
        let invocation = try SandboxLaunch.invocation(
            target: .cursor,
            sandboxEnabled: true,
            nonoAvailable: true,
            openPath: "/tmp/repo"
        )

        XCTAssertEqual(invocation.program, "/usr/bin/open")
        XCTAssertEqual(invocation.arguments, ["-a", "Cursor", "/tmp/repo"])
        XCTAssertFalse(invocation.usesNono)
        XCTAssertEqual(invocation.mechanism, .cursorNative)
    }

    func testCursorWithoutSandboxStillOpens() throws {
        let invocation = try SandboxLaunch.invocation(
            target: .cursor,
            sandboxEnabled: false,
            nonoAvailable: true
        )

        XCTAssertEqual(invocation.program, "/usr/bin/open")
        XCTAssertEqual(invocation.arguments, ["-a", "Cursor"])
        XCTAssertNil(invocation.mechanism)
    }

    func testWindsurfIsRejected() {
        XCTAssertThrowsError(
            try SandboxLaunch.invocation(
                target: .windsurf,
                sandboxEnabled: true,
                nonoAvailable: true
            )
        ) { error in
            guard case SandboxLaunch.LaunchError.unsupportedTarget("windsurf") = error else {
                return XCTFail("unexpected error: \(error)")
            }
        }
    }

    func testNonoLaunchHintMentionsOffsendRun() {
        let hint = SandboxLaunch.nonoLaunchHint(for: .claude)
        XCTAssertTrue(hint.contains("offsend run claude"))
        XCTAssertTrue(hint.contains("nono run --profile ./.offsend/nono/offsend-claude.json"))
    }
}
