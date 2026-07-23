import ArgumentParser
import DetectionCore
import Foundation
import MaskingCore
import OffsendRuntime
#if canImport(Darwin)
import Darwin
#endif

/// Writes AI-editor hook stdout/stderr, debug log entries, and optional notifications.
struct CheckHookEmitter {
    var quiet: Bool
    var debugHook: Bool
    var notify: Bool
    var secretsOnly: Bool
    var sealCopy: Bool
    var keyFile: String?
    var keyName: String?
    var workingDirectory: URL

    func emitFailOpen(
        adapter: CheckHookAdapter,
        reason: FailOpenReason,
        started: Date,
        policy: CheckHookPolicy,
        kind: CheckHookResponseRenderer.Kind
    ) {
        let rendered = CheckHookResponseRenderer.failOpen(
            adapter: adapter,
            reason: reason.code,
            kind: kind
        )
        writeHookOutput(rendered)
        logDebug(
            adapter: adapter,
            policy: policy,
            advice: nil,
            exitCode: rendered.exitCode,
            started: started,
            error: "\(reason.code): \(reason.debugDetail)"
        )
    }

    func emitReadGate(
        adapter: CheckHookAdapter,
        rawJSON: String,
        started: Date,
        policy: CheckHookPolicy,
        context: OffsendRuntimeContext,
        disabledDetectors: Set<SensitiveEntityType> = [],
        customDictionaries: [CustomDictionaryItem] = [],
        excludePatterns: [String] = [],
        projectRoot: URL? = nil,
        readConfig: OffsendProjectReadConfig? = nil
    ) async {
        let input: PromptReadGateInput
        do {
            input = try PromptReadGate.parse(json: rawJSON, adapter: adapter)
        } catch {
            emitFailOpen(
                adapter: adapter,
                reason: .invalidJSON,
                started: started,
                policy: policy,
                kind: .readGate
            )
            return
        }

        // Sealed copies are what a seal-mode deny points the agent at; reading
        // them must pass (contents are `{{…}}` tokens, no plaintext secrets).
        if SealCopyStore.isSealCopyPath(input.path) {
            let allowed = PromptReadGateDecision(path: input.path, allowed: true, reason: "")
            let rendered = PromptReadGateRenderer.render(decision: allowed, adapter: adapter)
            writeHookOutput(rendered)
            logDebug(
                adapter: adapter,
                policy: policy,
                advice: nil,
                exitCode: rendered.exitCode,
                started: started,
                error: "read_gate_seal_copy_allowed"
            )
            return
        }

        // check.exclude opts project paths out of the gate (fixtures, docs with
        // example keys, …) unless hooks.ignore_exclude re-enables full checks.
        if let projectRoot,
           PromptReadGate.isExcluded(
               path: input.path,
               excludePatterns: excludePatterns,
               projectRoot: projectRoot
           ) {
            let allowed = PromptReadGateDecision(path: input.path, allowed: true, reason: "")
            let rendered = PromptReadGateRenderer.render(decision: allowed, adapter: adapter)
            writeHookOutput(rendered)
            logDebug(
                adapter: adapter,
                policy: policy,
                advice: nil,
                exitCode: rendered.exitCode,
                started: started,
                error: "read_gate_excluded_path"
            )
            return
        }

        var decision = PromptReadGate.evaluatePath(input.path)
        var denyReason = decision.allowed ? nil : "read_gate_denied_path"
        var scanResult: OffsendTextCheckResult?

        if decision.allowed, let content = PromptReadGate.resolveContent(for: input) {
            let textResult = await OffsendCheckService(context: context).runText(
                content,
                failPolicy: .block,
                disabledDetectors: disabledDetectors,
                customDictionaries: customDictionaries
            )
            scanResult = textResult
            if let secretDeny = PromptReadGate.decisionForSecretEntities(
                path: input.path,
                entities: textResult.entities,
                secretsOnly: secretsOnly
            ) {
                decision = secretDeny
                denyReason = "read_gate_denied_secrets"
            }
        }

        // context.read.on_secret: seal — swap the dead-end deny for a deny that
        // hands the agent a sealed copy. Any failure (no key, no scannable
        // content, no entities) falls back to the plain deny above.
        if !decision.allowed,
           OffsendReadGateSecretMode(rawValue: readConfig?.onSecret ?? "") == .seal {
            if scanResult == nil, let content = PromptReadGate.resolveContent(for: input) {
                scanResult = await OffsendCheckService(context: context).runText(
                    content,
                    failPolicy: .block,
                    disabledDetectors: disabledDetectors,
                    customDictionaries: customDictionaries
                )
            }
            if let scanResult,
               let sealed = sealedReadDecision(input: input, scanResult: scanResult, context: context) {
                decision = sealed
                denyReason = "read_gate_denied_sealed_copy"
            }
        }

        let rendered = PromptReadGateRenderer.render(decision: decision, adapter: adapter)
        writeHookOutput(rendered)
        logDebug(
            adapter: adapter,
            policy: policy,
            advice: nil,
            exitCode: rendered.exitCode,
            started: started,
            error: denyReason
        )
    }

    /// Seals the scanned text and writes a 0600 temp copy. Returns nil when the
    /// key does not resolve, no secret entities were found, or sealing fails —
    /// callers keep the plain deny in that case (never weaker than block mode).
    private func sealedReadDecision(
        input: PromptReadGateInput,
        scanResult: OffsendTextCheckResult,
        context: OffsendRuntimeContext
    ) -> PromptReadGateDecision? {
        let gateEntities = PromptCheckAdviceBuilder.filterEntities(
            scanResult.entities,
            secretsOnly: secretsOnly
        )
        guard !gateEntities.isEmpty else { return nil }
        let resolvedKeyFile = keyFile.map {
            URL(fileURLWithPath: $0, relativeTo: workingDirectory).standardizedFileURL.path
        }
        do {
            let keyData = try SealKeyResolver.resolve(
                key: nil,
                keyFilePath: resolvedKeyFile,
                keyName: keyName
            ).data
            let sealed = try OffsendSealService(context: context).seal(
                text: scanResult.scannedText,
                entities: gateEntities,
                keyData: keyData
            )
            let written = try SealCopyStore.write(sealed.sealedText)
            let types = Array(Set(gateEntities.map(\.type.rawValue))).sorted()
            return PromptReadGate.sealedDecision(
                path: input.path,
                sealedCopyPath: written.fileURL.path,
                secretTypes: types
            )
        } catch {
            return nil
        }
    }

    func emitShellGate(
        adapter: CheckHookAdapter,
        rawJSON: String,
        started: Date,
        policy: CheckHookPolicy
    ) {
        let decision: PromptShellGateDecision
        do {
            decision = try PromptShellGate.evaluate(json: rawJSON, adapter: adapter)
        } catch {
            emitFailOpen(
                adapter: adapter,
                reason: .invalidJSON,
                started: started,
                policy: policy,
                kind: .shellGate
            )
            return
        }

        let rendered = PromptShellGateRenderer.render(decision: decision, adapter: adapter)
        writeHookOutput(rendered)
        logDebug(
            adapter: adapter,
            policy: policy,
            advice: nil,
            exitCode: rendered.exitCode,
            started: started,
            error: decision.allowed ? nil : "shell_gate_ask"
        )
    }

    func emitSubagentGate(
        adapter: CheckHookAdapter,
        rawJSON: String,
        started: Date,
        policy: CheckHookPolicy,
        context: OffsendRuntimeContext,
        subagentsConfig: OffsendProjectSubagentsConfig?,
        disabledDetectors: Set<SensitiveEntityType> = [],
        customDictionaries: [CustomDictionaryItem] = [],
        secretsOnly: Bool = true
    ) async {
        let call: PromptSubagentGateCall
        do {
            call = try PromptSubagentGate.parse(json: rawJSON, adapter: adapter)
        } catch {
            // Explicit `context.subagents.mode: deny` means the user asked to block; fail closed there.
            if OffsendContextEnforcementMode(rawValue: subagentsConfig?.mode ?? "") == .deny {
                let decision = PromptSubagentGateDecision(
                    call: PromptSubagentGateCall(task: ""),
                    permission: .deny,
                    reason: "Offsend: unrecognized subagent hook input denied (context.subagents.mode: deny).",
                    code: "invalid_input"
                )
                let rendered = PromptSubagentGateRenderer.render(decision: decision, adapter: adapter)
                writeHookOutput(rendered)
                logDebug(
                    adapter: adapter,
                    policy: policy,
                    advice: nil,
                    exitCode: rendered.exitCode,
                    started: started,
                    error: "subagent_gate_invalid_input"
                )
                return
            }
            emitFailOpen(
                adapter: adapter,
                reason: .invalidJSON,
                started: started,
                policy: policy,
                kind: .subagentGate
            )
            return
        }

        var secretTypes: [String] = []
        if !call.task.isEmpty {
            let textResult = await OffsendCheckService(context: context).runText(
                call.task,
                failPolicy: .block,
                disabledDetectors: disabledDetectors,
                customDictionaries: customDictionaries
            )
            let secrets = PromptCheckAdviceBuilder.filterEntities(
                textResult.entities,
                secretsOnly: secretsOnly
            )
            secretTypes = Array(Set(secrets.map(\.type.rawValue))).sorted()
        }

        let decision = PromptSubagentGate.evaluate(
            call: call,
            subagentsConfig: subagentsConfig,
            secretTypes: secretTypes
        )
        let rendered = PromptSubagentGateRenderer.render(decision: decision, adapter: adapter)
        writeHookOutput(rendered)
        logDebug(
            adapter: adapter,
            policy: policy,
            advice: nil,
            exitCode: rendered.exitCode,
            started: started,
            error: decision.allowed ? nil : "subagent_gate_\(decision.code)"
        )
    }

    func emitMCPGate(
        adapter: CheckHookAdapter,
        rawJSON: String,
        started: Date,
        policy: CheckHookPolicy,
        context: OffsendRuntimeContext,
        mcpConfig: OffsendProjectMCPConfig?,
        disabledDetectors: Set<SensitiveEntityType> = [],
        customDictionaries: [CustomDictionaryItem] = [],
        secretsOnly: Bool = true
    ) async {
        let call: PromptMCPGateCall
        do {
            call = try PromptMCPGate.parse(json: rawJSON, adapter: adapter)
        } catch {
            // Explicit `context.mcp.mode: deny` means the user asked to block; fail closed there.
            if OffsendContextEnforcementMode(rawValue: mcpConfig?.mode ?? "") == .deny {
                let decision = PromptMCPGateDecision(
                    call: PromptMCPGateCall(server: "unknown", tool: "unknown", toolInput: ""),
                    permission: .deny,
                    reason: "Offsend: unrecognized MCP hook input denied (context.mcp.mode: deny).",
                    code: "invalid_input"
                )
                let rendered = PromptMCPGateRenderer.render(decision: decision, adapter: adapter)
                writeHookOutput(rendered)
                logDebug(
                    adapter: adapter,
                    policy: policy,
                    advice: nil,
                    exitCode: rendered.exitCode,
                    started: started,
                    error: "mcp_gate_invalid_input"
                )
                return
            }
            emitFailOpen(
                adapter: adapter,
                reason: .invalidJSON,
                started: started,
                policy: policy,
                kind: .mcpGate
            )
            return
        }

        var secretTypes: [String] = []
        if !call.toolInput.isEmpty {
            let textResult = await OffsendCheckService(context: context).runText(
                call.toolInput,
                failPolicy: .block,
                disabledDetectors: disabledDetectors,
                customDictionaries: customDictionaries
            )
            let secrets = PromptCheckAdviceBuilder.filterEntities(
                textResult.entities,
                secretsOnly: secretsOnly
            )
            secretTypes = Array(Set(secrets.map(\.type.rawValue))).sorted()
        }

        let decision = PromptMCPGate.evaluate(
            call: call,
            mcpConfig: mcpConfig,
            secretTypes: secretTypes
        )
        let rendered = PromptMCPGateRenderer.render(decision: decision, adapter: adapter)
        writeHookOutput(rendered)
        logDebug(
            adapter: adapter,
            policy: policy,
            advice: nil,
            exitCode: rendered.exitCode,
            started: started,
            error: decision.allowed ? nil : "mcp_gate_\(decision.code)"
        )
    }

    func emitMCPResponseGate(
        adapter: CheckHookAdapter,
        rawJSON: String,
        started: Date,
        policy: CheckHookPolicy,
        context: OffsendRuntimeContext,
        mcpConfig: OffsendProjectMCPConfig?,
        disabledDetectors: Set<SensitiveEntityType> = [],
        customDictionaries: [CustomDictionaryItem] = [],
        secretsOnly: Bool = true
    ) async {
        let call: PromptMCPResponseCall
        do {
            call = try PromptMCPResponseGate.parse(json: rawJSON, adapter: adapter)
        } catch {
            // Post-hoc gate: nothing to block, so fail-open on malformed input.
            emitFailOpen(
                adapter: adapter,
                reason: .invalidJSON,
                started: started,
                policy: policy,
                kind: .mcpResponseGate
            )
            return
        }

        var secretTypes: [String] = []
        var sealedOutput: String?
        var sealedCount = 0
        if !call.responseText.isEmpty {
            let textResult = await OffsendCheckService(context: context).runText(
                call.responseText,
                failPolicy: .block,
                disabledDetectors: disabledDetectors,
                customDictionaries: customDictionaries
            )
            let secrets = PromptCheckAdviceBuilder.filterEntities(
                textResult.entities,
                secretsOnly: secretsOnly
            )
            secretTypes = Array(Set(secrets.map(\.type.rawValue))).sorted()

            let mode = OffsendMCPResponseMode(rawValue: mcpConfig?.responses ?? "") ?? .observe
            // Sealing a truncated response would replace output with a partial
            // text; renderer downgrades that case to a warning instead.
            if mode == .seal, !secrets.isEmpty, !call.truncated, adapter == .claude {
                let resolvedKeyFile = keyFile.map {
                    URL(fileURLWithPath: $0, relativeTo: workingDirectory).standardizedFileURL.path
                }
                if let keyData = try? SealKeyResolver.resolve(
                    key: nil,
                    keyFilePath: resolvedKeyFile,
                    keyName: keyName
                ).data,
                    let sealed = try? OffsendSealService(context: context).seal(
                        text: textResult.scannedText,
                        entities: secrets,
                        keyData: keyData
                    ) {
                    sealedOutput = sealed.sealedText
                    sealedCount = sealed.sealedCount
                }
            }
        }

        let decision = PromptMCPResponseGate.evaluate(
            call: call,
            mcpConfig: mcpConfig,
            secretTypes: secretTypes,
            sealedOutput: sealedOutput,
            sealedCount: sealedCount
        )
        let rendered = PromptMCPResponseGateRenderer.render(decision: decision, adapter: adapter)
        writeHookOutput(rendered)
        logDebug(
            adapter: adapter,
            policy: policy,
            advice: nil,
            exitCode: rendered.exitCode,
            started: started,
            error: decision.hasFindings
                ? (decision.sealed ? "mcp_response_sealed" : "mcp_response_secrets")
                : nil
        )
    }

    func emitAdapter(
        adapter: CheckHookAdapter,
        textResult: OffsendTextCheckResult,
        attachmentPaths: [String],
        context: OffsendRuntimeContext,
        started: Date,
        policy: CheckHookPolicy
    ) async throws {
        let shouldSeal = sealCopy || policy == .block
        let gateEntities = PromptCheckAdviceBuilder.filterEntities(
            textResult.entities,
            secretsOnly: secretsOnly
        )
        let attachmentAdvice = PromptAttachmentAdvisor.adviceLines(for: attachmentPaths)

        var sealedText: String?
        var sealedCopyPath: String?
        var sealFailureDetail: String?
        let sealAttempted = shouldSeal && !gateEntities.isEmpty
        if sealAttempted {
            let resolvedKeyFile = keyFile.map {
                URL(fileURLWithPath: $0, relativeTo: workingDirectory).standardizedFileURL.path
            }
            do {
                let keyData = try SealKeyResolver.resolve(
                    key: nil,
                    keyFilePath: resolvedKeyFile,
                    keyName: keyName
                ).data
                let sealed = try await OffsendSealService(context: context).seal(
                    text: textResult.scannedText,
                    entities: gateEntities,
                    keyData: keyData
                )
                sealedText = sealed.sealedText
                let written = try SealCopyStore.write(sealed.sealedText)
                sealedCopyPath = written.fileURL.path
                copyToClipboard(sealed.sealedText)
            } catch {
                sealFailureDetail = SealAvailabilityHint.userMessageDetail(
                    error: error,
                    key: nil,
                    keyFile: resolvedKeyFile,
                    keyName: keyName
                )
                if !quiet {
                    fputs(
                        SealAvailabilityHint.stderrMessage(
                            error: error,
                            key: nil,
                            keyFile: resolvedKeyFile,
                            keyName: keyName
                        ),
                        stderr
                    )
                }
            }
        }

        let advice = PromptCheckAdviceBuilder.build(
            entities: textResult.entities,
            policy: policy,
            sealedText: sealedText,
            sealedCopyPath: sealedCopyPath,
            secretsOnly: secretsOnly,
            attachmentAdviceLines: attachmentAdvice,
            sealAttempted: sealAttempted,
            sealFailureDetail: sealFailureDetail
        )
        let rendered = CheckHookAdapterRenderer.render(result: advice, adapter: adapter)

        if advice.hasFindings, notify {
            postNotification(body: advice.notificationBody)
        }

        writeHookOutput(rendered)
        logDebug(
            adapter: adapter,
            policy: policy,
            advice: advice,
            exitCode: rendered.exitCode,
            started: started,
            error: nil
        )

        if rendered.exitCode != 0 {
            throw ExitCode(rendered.exitCode)
        }
    }

    private func writeHookOutput(_ rendered: CheckHookAdapterOutput) {
        if !rendered.stderr.isEmpty, !quiet {
            fputs(rendered.stderr, stderr)
        }
        CLIOutput.writeStdout(rendered.stdout)
    }

    private func logDebug(
        adapter: CheckHookAdapter,
        policy: CheckHookPolicy,
        advice: PromptCheckAdviceResult?,
        exitCode: Int32,
        started: Date,
        error: String?
    ) {
        guard debugHook else { return }
        let latencyMs = Int(Date().timeIntervalSince(started) * 1000)
        HookDebugLog.append(
            HookDebugLog.Entry(
                adapter: adapter.rawValue,
                policy: policy.rawValue,
                findingCount: advice?.findingCount ?? 0,
                findingTypes: advice?.findings.map(\.type.rawValue) ?? [],
                exitCode: exitCode,
                latencyMs: latencyMs,
                error: error
            )
        )
    }

    private func copyToClipboard(_ text: String) {
        #if canImport(Darwin)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pbcopy")
        let input = Pipe()
        process.standardInput = input
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            input.fileHandleForWriting.write(Data(text.utf8))
            try input.fileHandleForWriting.close()
            process.waitUntilExit()
        } catch {}
        #endif
    }

    private func postNotification(body: String) {
        #if canImport(Darwin)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        let escaped = body
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        process.arguments = [
            "-e",
            "display notification \"\(escaped)\" with title \"Offsend\"",
        ]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        #endif
    }
}
