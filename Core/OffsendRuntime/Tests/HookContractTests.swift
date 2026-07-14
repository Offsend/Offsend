import DetectionCore
import XCTest
@testable import OffsendRuntime

final class HookContractTests: XCTestCase {
    private func fixtureURL(_ relative: String) throws -> URL {
        let source = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/HookInputs")
            .appendingPathComponent(relative)
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path), relative)
        return source
    }

    private func loadFixture(_ relative: String) throws -> String {
        try String(contentsOf: fixtureURL(relative), encoding: .utf8)
    }

    func testCursorFixtureExtractsPromptAndAttachments() throws {
        let json = try loadFixture("cursor/beforeSubmitPrompt.json")
        let payload = try PromptHookInput.payload(fromJSON: json, adapter: .cursor)
        XCTAssertTrue(payload.prompt.contains("AKIA"))
        XCTAssertEqual(payload.attachmentPaths, ["/repo/.env"])
    }

    func testClaudeCodexWindsurfFixturesExtractPrompt() throws {
        let claude = try PromptHookInput.payload(
            fromJSON: loadFixture("claude/UserPromptSubmit.json"),
            adapter: .claude
        )
        XCTAssertTrue(claude.prompt.contains("AKIA"))

        let codex = try PromptHookInput.payload(
            fromJSON: loadFixture("codex/UserPromptSubmit.json"),
            adapter: .codex
        )
        XCTAssertTrue(codex.prompt.contains("AKIA"))

        let windsurf = try PromptHookInput.payload(
            fromJSON: loadFixture("windsurf/pre_user_prompt.json"),
            adapter: .windsurf
        )
        XCTAssertTrue(windsurf.prompt.contains("AKIA"))
    }

    func testRendererSnapshotsAdviseAndSoftBlock() throws {
        let key = "AKIA1234567890ABCDEF"
        let entity = SensitiveEntity(
            type: .awsAccessKeyId,
            range: key.startIndex..<key.endIndex,
            value: key,
            confidence: 1,
            source: .secret
        )
        let advise = PromptCheckAdviceBuilder.build(entities: [entity], policy: .advise)
        let soft = PromptCheckAdviceBuilder.build(entities: [entity], policy: .softBlock)

        let cursorAdvise = CheckHookAdapterRenderer.render(result: advise, adapter: .cursor)
        XCTAssertTrue(cursorAdvise.stdout.contains("\"continue\":true") || cursorAdvise.stdout.contains("\"continue\": true"))

        let cursorSoft = CheckHookAdapterRenderer.render(result: soft, adapter: .cursor)
        XCTAssertTrue(cursorSoft.stdout.contains("\"continue\":false") || cursorSoft.stdout.contains("\"continue\": false"))
        XCTAssertTrue(cursorSoft.stdout.contains("user_message"))

        let claudeAdvise = CheckHookAdapterRenderer.render(result: advise, adapter: .claude)
        XCTAssertTrue(claudeAdvise.stdout.contains("systemMessage"))
    }

    func testReadGateDeniesEnvAllowsReadme() throws {
        let envCursor = try PromptReadGate.evaluate(
            json: loadFixture("cursor/beforeReadFile.env.json"),
            adapter: .cursor
        )
        XCTAssertFalse(envCursor.allowed)
        let envOut = PromptReadGateRenderer.render(decision: envCursor, adapter: .cursor)
        XCTAssertTrue(envOut.stdout.contains("deny"))

        let readme = try PromptReadGate.evaluate(
            json: loadFixture("cursor/beforeReadFile.readme.json"),
            adapter: .cursor
        )
        XCTAssertTrue(readme.allowed)

        let envClaude = try PromptReadGate.evaluate(
            json: loadFixture("claude/PreToolUse.Read.env.json"),
            adapter: .claude
        )
        XCTAssertFalse(envClaude.allowed)
        let claudeOut = PromptReadGateRenderer.render(decision: envClaude, adapter: .claude)
        XCTAssertTrue(claudeOut.stdout.contains("block"))

        let readmeClaude = try PromptReadGate.evaluate(
            json: loadFixture("claude/PreToolUse.Read.readme.json"),
            adapter: .claude
        )
        XCTAssertTrue(readmeClaude.allowed)
    }

    func testReadGateFailOpenUsesPermissionAllow() {
        let output = CheckHookResponseRenderer.failOpen(
            adapter: .cursor,
            reason: "invalid_json",
            kind: .readGate
        )
        XCTAssertTrue(output.stdout.contains("permission"))
        XCTAssertTrue(output.stdout.contains("allow"))
        XCTAssertFalse(output.stdout.contains("continue"))
    }

    func testFailOpenKindsMatchLegacyRenderers() {
        for adapter in CheckHookAdapter.allCases {
            let prompt = CheckHookAdapterRenderer.failOpen(adapter: adapter, reason: "invalid_json")
            let unifiedPrompt = CheckHookResponseRenderer.failOpen(
                adapter: adapter,
                reason: "invalid_json",
                kind: .promptSubmit
            )
            XCTAssertEqual(prompt, unifiedPrompt, adapter.rawValue)

            let read = PromptReadGateRenderer.failOpen(adapter: adapter, reason: "invalid_json")
            let unifiedRead = CheckHookResponseRenderer.failOpen(
                adapter: adapter,
                reason: "invalid_json",
                kind: .readGate
            )
            XCTAssertEqual(read, unifiedRead, adapter.rawValue)
        }
    }
}

final class FailOpenReasonTests: XCTestCase {
    func testFailOpenStderrUsesPublicCodeOnly() {
        let output = CheckHookAdapterRenderer.failOpen(adapter: .cursor, reason: "invalid_json")
        XCTAssertTrue(output.stderr.contains("invalid_json"))
        XCTAssertFalse(output.stderr.contains("/Users/"))
        XCTAssertTrue(output.stdout.contains("continue"))
    }

    func testInvalidHookPolicyReasonCode() {
        let reason = FailOpenReason.invalidHookPolicy("hard-block")
        XCTAssertEqual(reason.code, "invalid_hook_policy")
        XCTAssertTrue(reason.debugDetail.contains("hard-block"))
    }
}

final class HookLatencySmokeTests: XCTestCase {
    /// Warm invoke budget for a tiny adapter render path (not full CLI process).
    /// Baseline on Apple Silicon: typically &lt; 5ms; CI soft budget 500ms.
    func testWarmAdviceRenderUnderBudget() {
        let key = "AKIA1234567890ABCDEF"
        let entity = SensitiveEntity(
            type: .awsAccessKeyId,
            range: key.startIndex..<key.endIndex,
            value: key,
            confidence: 1,
            source: .secret
        )
        // Warmup
        _ = CheckHookAdapterRenderer.render(
            result: PromptCheckAdviceBuilder.build(entities: [entity], policy: .softBlock),
            adapter: .cursor
        )

        var samples: [Double] = []
        for _ in 0..<20 {
            let started = Date()
            let advice = PromptCheckAdviceBuilder.build(entities: [entity], policy: .softBlock)
            _ = CheckHookAdapterRenderer.render(result: advice, adapter: .cursor)
            samples.append(Date().timeIntervalSince(started) * 1000)
        }
        samples.sort()
        let p95 = samples[Int(Double(samples.count - 1) * 0.95)]
        // Soft budget — warn-style assert with generous CI margin (cold CI hosts vary).
        XCTAssertLessThan(p95, 500, "p95 advice+render was \(p95)ms; expected &lt; 500ms")
    }
}
