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
        XCTAssertTrue(claudeOut.stdout.contains("\"permissionDecision\":\"deny\""))
        XCTAssertTrue(claudeOut.stdout.contains("hookSpecificOutput"))

        let readmeClaude = try PromptReadGate.evaluate(
            json: loadFixture("claude/PreToolUse.Read.readme.json"),
            adapter: .claude
        )
        XCTAssertTrue(readmeClaude.allowed)
    }

    func testReadGateDeniesSensitiveDirectoryPaths() throws {
        let kube = try PromptReadGate.evaluate(
            json: #"{"file_path":"/Users/me/.kube/config"}"#,
            adapter: .cursor
        )
        XCTAssertFalse(kube.allowed)
        XCTAssertTrue(PromptReadGateRenderer.render(decision: kube, adapter: .cursor).stdout.contains("deny"))

        let docker = try PromptReadGate.evaluate(
            json: #"{"tool_input":{"file_path":"/Users/me/.docker/config.json"}}"#,
            adapter: .claude
        )
        XCTAssertFalse(docker.allowed)
        let dockerOut = PromptReadGateRenderer.render(decision: docker, adapter: .claude)
        XCTAssertTrue(dockerOut.stdout.contains("\"permissionDecision\":\"deny\""))
        XCTAssertTrue(dockerOut.stdout.contains("hookSpecificOutput"))

        let ordinary = try PromptReadGate.evaluate(
            json: #"{"file_path":"/repo/docker/config.json"}"#,
            adapter: .cursor
        )
        XCTAssertTrue(ordinary.allowed)
    }

    func testReadGateParsesCursorContent() throws {
        let input = try PromptReadGate.parse(
            json: loadFixture("cursor/beforeReadFile.indexWithKey.json"),
            adapter: .cursor
        )
        XCTAssertEqual(input.path, "/repo/index.js")
        XCTAssertTrue(input.content?.contains("sk-abcdefghijklmnopqrstuvwxyzABCDEF123456") == true)
        XCTAssertTrue(PromptReadGate.evaluatePath(input.path).allowed)
    }

    func testReadGateSealedDecisionRendersAgentMessage() throws {
        let decision = PromptReadGate.sealedDecision(
            path: "/repo/.env",
            sealedCopyPath: "/tmp/offsend-seal/sealed-abc.txt",
            secretTypes: ["awsSecretAccessKey"]
        )
        XCTAssertFalse(decision.allowed)

        // Cursor: deny plus agent_message with the sealed-copy path.
        let cursorOut = PromptReadGateRenderer.render(decision: decision, adapter: .cursor)
        let cursorRoot = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(cursorOut.stdout.utf8)) as? [String: Any]
        )
        XCTAssertEqual(cursorRoot["permission"] as? String, "deny")
        let agentMessage = try XCTUnwrap(cursorRoot["agent_message"] as? String)
        XCTAssertTrue(agentMessage.contains("/tmp/offsend-seal/sealed-abc.txt"))
        XCTAssertTrue(agentMessage.contains("offsend unseal"))

        // Claude: the sealed path must reach the model via permissionDecisionReason.
        let claudeOut = PromptReadGateRenderer.render(decision: decision, adapter: .claude)
        let claudeRoot = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(claudeOut.stdout.utf8)) as? [String: Any]
        )
        let hook = try XCTUnwrap(claudeRoot["hookSpecificOutput"] as? [String: Any])
        XCTAssertEqual(hook["permissionDecision"] as? String, "deny")
        let reason = try XCTUnwrap(hook["permissionDecisionReason"] as? String)
        XCTAssertTrue(reason.contains("/tmp/offsend-seal/sealed-abc.txt"))
    }

    func testPlainDenyHasNoAgentMessageField() throws {
        let decision = PromptReadGate.evaluatePath("/Users/me/.env")
        XCTAssertFalse(decision.allowed)
        let out = PromptReadGateRenderer.render(decision: decision, adapter: .cursor)
        let root = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(out.stdout.utf8)) as? [String: Any]
        )
        XCTAssertNil(root["agent_message"])
    }

    func testReadGateDeniesSecretEntitiesInContent() {
        let key = "sk-abcdefghijklmnopqrstuvwxyzABCDEF123456"
        let entity = SensitiveEntity(
            type: .openAIAPIKey,
            range: key.startIndex..<key.endIndex,
            value: key,
            confidence: 0.99,
            source: .secret
        )
        let decision = PromptReadGate.decisionForSecretEntities(
            path: "/repo/index.js",
            entities: [entity],
            secretsOnly: true
        )
        XCTAssertEqual(decision?.allowed, false)
        XCTAssertTrue(decision?.reason.contains("openAIAPIKey") == true)
        XCTAssertTrue(
            PromptReadGateRenderer.render(decision: decision!, adapter: .cursor).stdout.contains("deny")
        )
    }

    func testReadGateAllowsWhenNoSecretEntities() {
        let decision = PromptReadGate.decisionForSecretEntities(
            path: "/repo/index.js",
            entities: [],
            secretsOnly: true
        )
        XCTAssertNil(decision)
    }

    func testReadGateResolvesRelativePathAgainstCwd() {
        let resolved = PromptReadGate.resolveFilesystemPath("index.js", cwd: "/Users/me/repo")
        XCTAssertEqual(resolved, "/Users/me/repo/index.js")
        XCTAssertEqual(
            PromptReadGate.resolveFilesystemPath("/abs/file.env", cwd: "/Users/me/repo"),
            "/abs/file.env"
        )
    }

    func testReadGateDeniesSymlinkToSensitiveTarget() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("offsend-read-gate-symlink-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let env = root.appendingPathComponent(".env")
        let link = root.appendingPathComponent("notes.txt")
        try "SECRET=1\n".write(to: env, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: env)

        let decision = PromptReadGate.evaluatePath(link.path)
        XCTAssertFalse(decision.allowed)
        XCTAssertTrue(decision.reason.contains(".env"))

        let ordinary = root.appendingPathComponent("readme.md")
        try "# hi\n".write(to: ordinary, atomically: true, encoding: .utf8)
        XCTAssertTrue(PromptReadGate.evaluatePath(ordinary.path).allowed)
    }

    func testReadGatePathHeuristicsMissRenamedCopyButContentScanCatchesSecrets() throws {
        // Renamed copies are not symlinks: path heuristics alone miss them; content scan is the backstop.
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("offsend-read-gate-rename-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let copy = root.appendingPathComponent("notes.txt")
        let key = "sk-abcdefghijklmnopqrstuvwxyzABCDEF123456"
        try "OPENAI_API_KEY=\(key)\n".write(to: copy, atomically: true, encoding: .utf8)

        XCTAssertTrue(
            PromptReadGate.evaluatePath(copy.path).allowed,
            "Renamed copy must not be denied by path heuristics alone"
        )

        let entity = SensitiveEntity(
            type: .openAIAPIKey,
            range: key.startIndex..<key.endIndex,
            value: key,
            confidence: 0.99,
            source: .secret
        )
        let contentDecision = PromptReadGate.decisionForSecretEntities(
            path: copy.path,
            entities: [entity],
            secretsOnly: true
        )
        XCTAssertEqual(contentDecision?.allowed, false)
        XCTAssertTrue(contentDecision?.reason.contains("openAIAPIKey") == true)
    }

    func testReadGateIgnoresHighEntropyWhenSecretsOnly() {
        let value = String(repeating: "Ab1+", count: 20)
        let entity = SensitiveEntity(
            type: .highEntropyString,
            range: value.startIndex..<value.endIndex,
            value: value,
            confidence: 0.65,
            source: .secret
        )
        XCTAssertNil(
            PromptReadGate.decisionForSecretEntities(
                path: "/repo/noise.js",
                entities: [entity],
                secretsOnly: true
            )
        )
    }

    func testReadGateResolveContentPrefersPayloadOverDisk() throws {
        let input = PromptReadGateInput(
            path: "/nonexistent/path/that/should/not/be/read.js",
            content: "const API_KEY = \"sk-abcdefghijklmnopqrstuvwxyzABCDEF123456\";"
        )
        let content = PromptReadGate.resolveContent(for: input)
        XCTAssertEqual(content, input.content)
    }

    func testReadGateKeepsFullHookProvidedContentPastLegacy50KBoundary() {
        let key = "AKIA1234567890ABCDEF"
        let content = String(repeating: "a", count: 55_000) + key
        let input = PromptReadGateInput(path: "/repo/large.txt", content: content)

        XCTAssertFalse(PromptReadGate.contentExceedsLimit(for: input))
        XCTAssertEqual(PromptReadGate.resolveContent(for: input), content)
    }

    func testReadGateMarksOversizedDiskFileUnsafe() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("offsend-oversized-\(UUID().uuidString).txt")
        let data = Data(repeating: 0x61, count: PromptReadGate.maxContentBytes + 1)
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let input = PromptReadGateInput(path: url.path, content: nil)
        XCTAssertTrue(PromptReadGate.contentExceedsLimit(for: input))
        XCTAssertEqual(PromptReadGate.resolveContentResult(for: input), .oversized)
        XCTAssertNil(PromptReadGate.resolveContent(for: input))
        XCTAssertFalse(PromptReadGate.oversizedDecision(path: url.path).allowed)
    }

    /// Hook input over the stdin byte limit must deny, not fail open: for
    /// Cursor the file body rides inside the hook JSON, so an oversized file
    /// would otherwise bypass the content scan entirely.
    func testReadGateOversizedStdinDeniesForCursorAndClaude() throws {
        let decision = PromptReadGate.oversizedStdinDecision()
        XCTAssertFalse(decision.allowed)

        let cursor = PromptReadGateRenderer.render(decision: decision, adapter: .cursor)
        let cursorRoot = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(cursor.stdout.utf8)) as? [String: Any]
        )
        XCTAssertEqual(cursorRoot["permission"] as? String, "deny")

        let claude = PromptReadGateRenderer.render(decision: decision, adapter: .claude)
        let claudeRoot = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(claude.stdout.utf8)) as? [String: Any]
        )
        let hook = try XCTUnwrap(claudeRoot["hookSpecificOutput"] as? [String: Any])
        XCTAssertEqual(hook["permissionDecision"] as? String, "deny")
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
