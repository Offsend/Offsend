import DetectionCore
import XCTest
@testable import OffsendRuntime

final class PromptCheckAdviceTests: XCTestCase {
    func testRemediationMappingForSecretTypes() {
        let moveToEnv: [SensitiveEntityType] = [
            .apiKeyGeneric, .openAIAPIKey, .awsAccessKeyId, .githubToken, .slackToken,
            .stripeKey, .jwt, .databaseURLWithPassword, .bearerToken, .highEntropyString,
        ]
        for type in moveToEnv {
            XCTAssertEqual(PromptCheckAdviceBuilder.remediation(for: type), .moveToEnv, type.rawValue)
        }
        XCTAssertEqual(PromptCheckAdviceBuilder.remediation(for: .sshPrivateKey), .addToIgnore)
        XCTAssertEqual(PromptCheckAdviceBuilder.remediation(for: .privateKey), .addToIgnore)
        XCTAssertEqual(PromptCheckAdviceBuilder.remediation(for: .email), .dontPaste)
    }

    func testFingerprintIsTypeOnly() {
        XCTAssertEqual(PromptCheckAdviceBuilder.fingerprint(for: .openAIAPIKey), "openAIAPIKey")
        let token = "sk-abcdefghijklmnop"
        let entity = SensitiveEntity(
            type: .openAIAPIKey,
            range: token.startIndex..<token.endIndex,
            value: token,
            confidence: 1,
            source: .secret
        )
        let result = PromptCheckAdviceBuilder.build(entities: [entity], policy: .advise)
        XCTAssertFalse(result.findings[0].message.contains("sk-"))
        XCTAssertFalse(result.notificationBody.contains("sk-"))
    }

    func testSecretsOnlyFiltersPIIAndHighEntropy() {
        let email = "a@b.co"
        let key = "AKIA1234567890ABCDEF"
        let entropy = "a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6"
        let entities = [
            SensitiveEntity(
                type: .email,
                range: email.startIndex..<email.endIndex,
                value: email,
                confidence: 1,
                source: .regex
            ),
            SensitiveEntity(
                type: .awsAccessKeyId,
                range: key.startIndex..<key.endIndex,
                value: key,
                confidence: 1,
                source: .secret
            ),
            SensitiveEntity(
                type: .highEntropyString,
                range: entropy.startIndex..<entropy.endIndex,
                value: entropy,
                confidence: 0.5,
                source: .secret
            ),
        ]
        let filtered = PromptCheckAdviceBuilder.filterEntities(entities, secretsOnly: true)
        XCTAssertEqual(filtered.map(\.type), [.awsAccessKeyId])
    }

    func testBlockMessageMentionsSealUnavailableWithoutPath() {
        let key = "AKIA1234567890ABCDEF"
        let entity = SensitiveEntity(
            type: .awsAccessKeyId,
            range: key.startIndex..<key.endIndex,
            value: key,
            confidence: 1,
            source: .secret
        )
        let withoutKey = PromptCheckAdviceBuilder.build(
            entities: [entity],
            policy: .block,
            sealAttempted: true
        )
        XCTAssertTrue(withoutKey.userMessage.contains("Prompt blocked; seal unavailable"))
        XCTAssertTrue(withoutKey.userMessage.contains(SealKeyPaths.defaultKeyInstallHint))
        XCTAssertFalse(withoutKey.userMessage.contains("/tmp/"))

        let badKey = PromptCheckAdviceBuilder.build(
            entities: [entity],
            policy: .block,
            sealAttempted: true,
            sealFailureDetail: "could not read key file at /secret/path.key"
        )
        XCTAssertTrue(badKey.userMessage.contains("could not read key file"))
        XCTAssertFalse(badKey.userMessage.contains(SealKeyPaths.defaultKeyInstallHint))

        let withSeal = PromptCheckAdviceBuilder.build(
            entities: [entity],
            policy: .block,
            sealedText: "{{SEALED}}",
            sealedCopyPath: "/tmp/offsend-seal/sealed-x.txt",
            sealAttempted: true
        )
        XCTAssertTrue(withSeal.userMessage.contains("clipboard"))
        XCTAssertFalse(withSeal.userMessage.contains("/tmp/offsend-seal/sealed-x.txt"))

        let soft = PromptCheckAdviceBuilder.build(entities: [entity], policy: .softBlock)
        XCTAssertFalse(soft.userMessage.contains("seal"))

        let attachmentOnly = PromptCheckAdviceBuilder.build(
            entities: [],
            policy: .block,
            attachmentAdviceLines: ["attachment (.env): do not attach"],
            sealAttempted: false
        )
        XCTAssertFalse(attachmentOnly.userMessage.contains("seal unavailable"))
    }
}

final class PromptHookInputTests: XCTestCase {
    func testExtractsCursorPromptAndAttachments() throws {
        let json = #"{"prompt":"hello secret","attachments":[{"type":"file","file_path":"/tmp/.env"}]}"#
        let payload = try PromptHookInput.payload(fromJSON: json, adapter: .cursor)
        XCTAssertEqual(payload.prompt, "hello secret")
        XCTAssertEqual(payload.attachmentPaths, ["/tmp/.env"])
    }

    func testExtractsClaudeAndCodexPrompt() throws {
        let json = #"{"hook_event_name":"UserPromptSubmit","prompt":"ship it"}"#
        XCTAssertEqual(try PromptHookInput.prompt(fromJSON: json, adapter: .claude), "ship it")
        XCTAssertEqual(try PromptHookInput.prompt(fromJSON: json, adapter: .codex), "ship it")
    }

    func testExtractsWindsurfPrompt() throws {
        let json = #"{"agent_action_name":"pre_user_prompt","tool_info":{"user_prompt":"cascade hi"}}"#
        XCTAssertEqual(try PromptHookInput.prompt(fromJSON: json, adapter: .windsurf), "cascade hi")
    }

    func testMissingPromptFails() {
        XCTAssertThrowsError(try PromptHookInput.prompt(fromJSON: #"{"foo":1}"#, adapter: .claude)) { error in
            XCTAssertEqual(error as? PromptHookInputError, .missingPrompt(adapter: .claude))
        }
    }

    func testInvalidJSONFails() {
        XCTAssertThrowsError(try PromptHookInput.prompt(fromJSON: "not-json", adapter: .cursor)) { error in
            XCTAssertEqual(error as? PromptHookInputError, .invalidJSON)
        }
    }
}

final class CheckHookAdapterRendererTests: XCTestCase {
    private func findingResult(policy: CheckHookPolicy) -> PromptCheckAdviceResult {
        PromptCheckAdviceResult(
            policy: policy,
            findings: [
                PromptCheckAdviceFinding(
                    type: .openAIAPIKey,
                    fingerprint: "openAIAPIKey",
                    remediation: .moveToEnv,
                    message: "openAIAPIKey: move to env"
                ),
            ],
            userMessage: "Offsend: found secrets"
        )
    }

    func testMatrixAdapterPolicySnapshots() {
        let cases: [(CheckHookAdapter, CheckHookPolicy, (CheckHookAdapterOutput) -> Void)] = [
            (.cursor, .advise, { out in
                XCTAssertEqual(out.exitCode, 0)
                XCTAssertTrue(out.stdout.contains("continue"))
            }),
            (.cursor, .softBlock, { out in
                XCTAssertEqual(out.exitCode, 0)
                XCTAssertTrue(out.stdout.contains("false"))
            }),
            (.cursor, .block, { out in
                XCTAssertEqual(out.exitCode, 0)
                XCTAssertTrue(out.stdout.contains("user_message"))
            }),
            (.claude, .advise, { out in
                XCTAssertTrue(out.stdout.contains("systemMessage"))
            }),
            (.claude, .softBlock, { out in
                XCTAssertTrue(out.stdout.contains("decision"))
            }),
            (.codex, .advise, { out in
                XCTAssertTrue(out.stdout.contains("systemMessage"))
            }),
            (.windsurf, .advise, { out in
                XCTAssertEqual(out.exitCode, 0)
            }),
            (.windsurf, .block, { out in
                XCTAssertEqual(out.exitCode, OffsendExitCode.error.rawValue)
            }),
        ]

        for (adapter, policy, assert) in cases {
            let output = CheckHookAdapterRenderer.render(result: findingResult(policy: policy), adapter: adapter)
            assert(output)
        }
    }

    func testFailOpenAllowsAllAdapters() {
        for adapter in CheckHookAdapter.allCases {
            let output = CheckHookAdapterRenderer.failOpen(adapter: adapter, reason: "invalid_json")
            XCTAssertEqual(output.exitCode, 0, adapter.rawValue)
            XCTAssertTrue(output.stderr.contains("fail-open"))
            XCTAssertTrue(output.stderr.contains("invalid_json"))
            XCTAssertFalse(output.stderr.contains("/Users/"))
        }
    }

    func testEmptyFindingsAllow() {
        let empty = PromptCheckAdviceResult(policy: .softBlock, findings: [], userMessage: "clean")
        let cursor = CheckHookAdapterRenderer.render(result: empty, adapter: .cursor)
        XCTAssertTrue(cursor.stdout.contains("true"))
        let windsurf = CheckHookAdapterRenderer.render(result: empty, adapter: .windsurf)
        XCTAssertEqual(windsurf.exitCode, 0)
    }
}
