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
        customDictionaries: [CustomDictionaryItem] = []
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

        var decision = PromptReadGate.evaluatePath(input.path)
        var denyReason = decision.allowed ? nil : "read_gate_denied_path"

        if decision.allowed, let content = PromptReadGate.resolveContent(for: input) {
            let textResult = await OffsendCheckService(context: context).runText(
                content,
                failPolicy: .block,
                disabledDetectors: disabledDetectors,
                customDictionaries: customDictionaries
            )
            if let secretDeny = PromptReadGate.decisionForSecretEntities(
                path: input.path,
                entities: textResult.entities,
                secretsOnly: secretsOnly
            ) {
                decision = secretDeny
                denyReason = "read_gate_denied_secrets"
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
