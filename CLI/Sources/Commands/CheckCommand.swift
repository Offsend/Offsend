import ArgumentParser
import Foundation
import MaskingCore
import OffsendRuntime
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

struct Check: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Scan files or prompt text for sensitive data before sharing or committing."
    )

    @Argument(help: "File or directory paths to scan. Directories are scanned recursively.")
    var paths: [String] = []

    @Flag(name: .long, help: "Scan only staged files in the current git repository.")
    var staged = false

    @Flag(name: .long, help: "Read prompt/text from stdin instead of file paths.")
    var stdin = false

    @Flag(name: .long, help: "Also run workspace policy checks on the repository root.")
    var policy = false

    @Option(name: .long, help: "Exit with failure when findings reach this level (block, warn, none).")
    var failOn: String?

    @Option(name: .long, help: "Output format (text, json). Ignored when --adapter is set.")
    var format: String = CheckOutputFormat.text.rawValue

    // AI-editor hook plumbing below. These flags are used by installed hook
    // wrappers (`offsend hook install`), not by people, so they are hidden
    // from `check --help` while remaining fully functional.
    @Option(
        name: .long,
        help: ArgumentHelp(
            "AI-editor hook adapter (cursor, claude, windsurf, codex). Implies reading hook JSON from stdin.",
            visibility: .hidden
        )
    )
    var adapter: String?

    @Option(
        name: .long,
        help: ArgumentHelp(
            "Hook policy when --adapter is set (advise, soft-block, block). block = soft-block UI plus seal-copy when a key is set.",
            visibility: .hidden
        )
    )
    var hookPolicy: String?

    @Flag(
        name: .long,
        inversion: .prefixedNo,
        help: ArgumentHelp(
            "Show a macOS notification when --adapter finds issues (default: on for Darwin).",
            visibility: .hidden
        )
    )
    var notify = true

    @Flag(
        name: .long,
        inversion: .prefixedNo,
        help: "With --gate-secrets or --adapter, only report secret-shaped findings (default: on)."
    )
    var secretsOnly = true

    @Flag(
        name: .long,
        help: ArgumentHelp(
            "With --adapter, write a sealed copy to a private temp file + clipboard.",
            visibility: .hidden
        )
    )
    var sealCopy = false

    @Flag(
        name: .long,
        help: ArgumentHelp(
            "Append adapter diagnostics to the Offsend hook debug log (no secret values).",
            visibility: .hidden
        )
    )
    var debugHook = false

    @Flag(
        name: .long,
        help: "With --stdin, print secret-gate JSON instead of the risk report."
    )
    var gateSecrets = false

    @Flag(
        name: .long,
        help: ArgumentHelp(
            "File-read gate for editor hooks: sensitive paths + secret content scan (requires --adapter cursor|claude).",
            visibility: .hidden
        )
    )
    var readGate = false

    @Flag(
        name: .long,
        help: ArgumentHelp(
            "Sensitive-path gate for editor shell hooks; findings ask for confirmation (requires --adapter cursor|claude).",
            visibility: .hidden
        )
    )
    var shellGate = false

    @Flag(
        name: .long,
        help: ArgumentHelp(
            "MCP tool-call gate for editor hooks: server policy + path/secret scan in args (requires --adapter cursor|claude).",
            visibility: .hidden
        )
    )
    var mcpGate = false

    @Flag(
        name: .long,
        help: ArgumentHelp(
            "Subagent spawn gate: secret-scan the task prompt (requires --adapter cursor).",
            visibility: .hidden
        )
    )
    var subagentGate = false

    @Option(
        name: .long,
        help: ArgumentHelp(
            "Path to a seal key file (for --seal-copy / --hook-policy block).",
            visibility: .hidden
        )
    )
    var keyFile: String?

    @Option(
        name: .long,
        help: ArgumentHelp(
            "Named seal key in ~/.offsend/keys/NAME.key.",
            visibility: .hidden
        )
    )
    var keyName: String?

    @Flag(name: .long, help: "Only print findings and errors.")
    var quiet = false

    @Flag(name: .long, help: "List every finding and skipped file individually instead of a summary.")
    var verbose = false

    @Option(name: .long, help: "Working directory used for relative paths.")
    var workingDirectory: String?

    mutating func run() async throws {
        let hookAdapter = CLIParse.checkHookAdapter(adapter)
        let usesStdin = stdin || hookAdapter != nil

        if usesStdin {
            try await runStdinPath(adapter: hookAdapter)
            return
        }

        try await runFilePath()
    }

    private func runStdinPath(adapter: CheckHookAdapter?) async throws {
        let started = Date()
        validateStdinOptions(adapter: adapter)

        if let adapter, let hookPolicy, CheckHookPolicy(rawValue: hookPolicy) == nil {
            hookEmitter().emitFailOpen(
                adapter: adapter,
                reason: .invalidHookPolicy(hookPolicy),
                started: started,
                policy: CheckHookPolicy.defaultPolicy(for: adapter),
                kind: hookKind
            )
            return
        }
        let rawText: String
        do {
            rawText = try CLIStdin.readUTF8()
        } catch let error as CLIStdin.ReadError {
            if let adapter {
                hookEmitter().emitFailOpen(
                    adapter: adapter,
                    reason: error.failOpenReason,
                    started: started,
                    policy: resolvedHookPolicy(for: adapter),
                    kind: hookKind
                )
                return
            }
            CLIError.exit(.error, message: error.message)
        }

        if readGate, let adapter {
            let (context, projectConfig) = loadStdinRuntime(adapter: adapter, started: started)
            guard let context else { return }
            let resolved = OptionsResolver.resolveCheckOptions(
                overrides: CLICheckOverrides(
                    policySpecified: false,
                    policyValue: false,
                    failOn: CLIParse.failPolicy(failOn)
                ),
                projectConfig: projectConfig,
                staged: false
            )
            await hookEmitter().emitReadGate(
                adapter: adapter,
                rawJSON: rawText,
                started: started,
                policy: resolvedHookPolicy(for: adapter),
                context: context,
                disabledDetectors: resolved.disabledDetectors,
                customDictionaries: resolved.customDictionaries
            )
            return
        }

        if shellGate, let adapter {
            hookEmitter().emitShellGate(
                adapter: adapter,
                rawJSON: rawText,
                started: started,
                policy: resolvedHookPolicy(for: adapter)
            )
            return
        }

        if mcpGate, let adapter {
            let (context, projectConfig) = loadStdinRuntime(adapter: adapter, started: started)
            guard let context else { return }
            let resolved = OptionsResolver.resolveCheckOptions(
                overrides: CLICheckOverrides(
                    policySpecified: false,
                    policyValue: false,
                    failOn: CLIParse.failPolicy(failOn)
                ),
                projectConfig: projectConfig,
                staged: false
            )
            await hookEmitter().emitMCPGate(
                adapter: adapter,
                rawJSON: rawText,
                started: started,
                policy: resolvedHookPolicy(for: adapter),
                context: context,
                mcpConfig: projectConfig?.context?.mcp,
                disabledDetectors: resolved.disabledDetectors,
                customDictionaries: resolved.customDictionaries,
                secretsOnly: secretsOnly
            )
            return
        }

        if subagentGate, let adapter {
            let (context, projectConfig) = loadStdinRuntime(adapter: adapter, started: started)
            guard let context else { return }
            let resolved = OptionsResolver.resolveCheckOptions(
                overrides: CLICheckOverrides(
                    policySpecified: false,
                    policyValue: false,
                    failOn: CLIParse.failPolicy(failOn)
                ),
                projectConfig: projectConfig,
                staged: false
            )
            await hookEmitter().emitSubagentGate(
                adapter: adapter,
                rawJSON: rawText,
                started: started,
                policy: resolvedHookPolicy(for: adapter),
                context: context,
                subagentsConfig: projectConfig?.context?.subagents,
                disabledDetectors: resolved.disabledDetectors,
                customDictionaries: resolved.customDictionaries,
                secretsOnly: secretsOnly
            )
            return
        }

        let promptPayload = parsePromptPayload(rawText: rawText, adapter: adapter, started: started)
        if promptPayload == nil, adapter != nil {
            return
        }

        let (context, projectConfig) = loadStdinRuntime(adapter: adapter, started: started)
        if context == nil {
            return
        }

        let validatedFailOn = CLIParse.failPolicy(failOn)
        let resolved = OptionsResolver.resolveCheckOptions(
            overrides: CLICheckOverrides(
                policySpecified: false,
                policyValue: false,
                failOn: validatedFailOn
            ),
            projectConfig: projectConfig,
            staged: false
        )

        let service = OffsendCheckService(context: context!)
        let scanText = promptScanText(payload: promptPayload, fallback: rawText)
        let textResult = await service.runText(
            scanText,
            failPolicy: resolved.failPolicy,
            disabledDetectors: resolved.disabledDetectors,
            customDictionaries: resolved.customDictionaries
        )

        if let adapter {
            try await hookEmitter().emitAdapter(
                adapter: adapter,
                textResult: textResult,
                attachmentPaths: promptPayload?.attachmentPaths ?? [],
                context: context!,
                started: started,
                policy: resolvedHookPolicy(for: adapter)
            )
            return
        }

        if gateSecrets {
            try emitGateSecretsJSON(from: textResult)
            return
        }

        try renderStdinReport(textResult)
    }

    private func validateStdinOptions(adapter: CheckHookAdapter?) {
        if staged {
            CLIError.exit(.error, message: "--stdin/--adapter cannot be combined with --staged.")
        }
        if !paths.isEmpty {
            CLIError.exit(.error, message: "--stdin/--adapter cannot be combined with file paths.")
        }
        if policy {
            CLIError.exit(.error, message: "--stdin/--adapter cannot be combined with --policy.")
        }
        if hookPolicy != nil, adapter == nil {
            CLIError.exit(.error, message: "--hook-policy requires --adapter.")
        }
        if sealCopy, adapter == nil {
            CLIError.exit(.error, message: "--seal-copy requires --adapter.")
        }
        if debugHook, adapter == nil {
            CLIError.exit(.error, message: "--debug-hook requires --adapter.")
        }
        if gateSecrets, adapter != nil {
            CLIError.exit(.error, message: "--gate-secrets cannot be combined with --adapter.")
        }
        if readGate, adapter == nil {
            CLIError.exit(.error, message: "--read-gate requires --adapter.")
        }
        if readGate, let adapter, adapter != .cursor, adapter != .claude {
            CLIError.exit(.error, message: "--read-gate supports --adapter cursor or claude.")
        }
        if shellGate, adapter == nil {
            CLIError.exit(.error, message: "--shell-gate requires --adapter.")
        }
        if shellGate, let adapter, adapter != .cursor, adapter != .claude {
            CLIError.exit(.error, message: "--shell-gate supports --adapter cursor or claude.")
        }
        if mcpGate, adapter == nil {
            CLIError.exit(.error, message: "--mcp-gate requires --adapter.")
        }
        if mcpGate, let adapter, adapter != .cursor, adapter != .claude {
            CLIError.exit(.error, message: "--mcp-gate supports --adapter cursor or claude.")
        }
        if subagentGate, adapter == nil {
            CLIError.exit(.error, message: "--subagent-gate requires --adapter.")
        }
        if subagentGate, let adapter, adapter != .cursor {
            CLIError.exit(.error, message: "--subagent-gate supports --adapter cursor only.")
        }
        let gateFlags = [readGate, shellGate, mcpGate, subagentGate].filter { $0 }.count
        if gateFlags > 1 {
            CLIError.exit(
                .error,
                message: "--read-gate, --shell-gate, --mcp-gate, and --subagent-gate are mutually exclusive."
            )
        }
    }

    private var hookKind: CheckHookResponseRenderer.Kind {
        if subagentGate { return .subagentGate }
        if mcpGate { return .mcpGate }
        if shellGate { return .shellGate }
        if readGate { return .readGate }
        return .promptSubmit
    }

    private struct ParsedPromptPayload {
        let prompt: String
        let attachmentPaths: [String]
        let cwd: String?
    }

    /// Prompt text plus bounded contents of `@mentions` / attachments so secrets in
    /// referenced files are caught before the model turn starts.
    private func promptScanText(payload: ParsedPromptPayload?, fallback: String) -> String {
        guard let payload else { return fallback }
        let cwd = payload.cwd
            ?? workingDirectory
            ?? FileManager.default.currentDirectoryPath
        var parts = [payload.prompt]
        for path in payload.attachmentPaths {
            let resolved = PromptReadGate.resolveFilesystemPath(path, cwd: cwd)
            if let content = PromptReadGate.loadContentPrefix(fromPath: resolved) {
                parts.append(content)
            }
        }
        return parts.joined(separator: "\n")
    }

    private func parsePromptPayload(
        rawText: String,
        adapter: CheckHookAdapter?,
        started: Date
    ) -> ParsedPromptPayload? {
        guard let adapter else { return nil }

        do {
            let payload = try PromptHookInput.payload(fromJSON: rawText, adapter: adapter)
            return ParsedPromptPayload(
                prompt: payload.prompt,
                attachmentPaths: payload.attachmentPaths,
                cwd: payload.cwd
            )
        } catch let error as PromptHookInputError {
            hookEmitter().emitFailOpen(
                adapter: adapter,
                reason: FailOpenReason.fromPromptHookInputError(error),
                started: started,
                policy: resolvedHookPolicy(for: adapter),
                kind: .promptSubmit
            )
            return nil
        } catch {
            hookEmitter().emitFailOpen(
                adapter: adapter,
                reason: FailOpenReason(code: "invalid_json", debugDetail: error.localizedDescription),
                started: started,
                policy: resolvedHookPolicy(for: adapter),
                kind: .promptSubmit
            )
            return nil
        }
    }

    private func loadStdinRuntime(
        adapter: CheckHookAdapter?,
        started: Date
    ) -> (OffsendRuntimeContext?, OffsendProjectConfig?) {
        let context: OffsendRuntimeContext
        do {
            context = try OffsendRuntimeContext.load()
        } catch {
            if let adapter {
                hookEmitter().emitFailOpen(
                    adapter: adapter,
                    reason: .settingsUnavailable(error.localizedDescription),
                    started: started,
                    policy: resolvedHookPolicy(for: adapter),
                    kind: hookKind
                )
                return (nil, nil)
            }
            CLIError.exit(.error, message: "Failed to load Offsend settings: \(error.localizedDescription)")
        }

        let workingURL = URL(
            fileURLWithPath: workingDirectory ?? FileManager.default.currentDirectoryPath
        ).standardizedFileURL

        let projectConfig: OffsendProjectConfig?
        do {
            projectConfig = try ProjectConfigLoader().load(from: workingURL)
        } catch {
            if let adapter {
                hookEmitter().emitFailOpen(
                    adapter: adapter,
                    reason: .projectConfigInvalid(error.localizedDescription),
                    started: started,
                    policy: resolvedHookPolicy(for: adapter),
                    kind: hookKind
                )
                return (nil, nil)
            }
            CLIError.exit(
                .error,
                message: "Failed to load \(ProjectConfigLoader.filename): \(error.localizedDescription)"
            )
        }

        return (context, projectConfig)
    }

    private func emitGateSecretsJSON(from textResult: OffsendTextCheckResult) throws {
        let gateEntities = PromptCheckAdviceBuilder.filterEntities(
            textResult.entities,
            secretsOnly: secretsOnly
        )
        let advice = PromptCheckAdviceBuilder.build(
            entities: gateEntities,
            policy: .advise,
            secretsOnly: secretsOnly
        )
        let payload: [String: Any] = [
            "findingCount": advice.findingCount,
            "findingTypes": advice.findings.map(\.type.rawValue),
            "userMessage": advice.userMessage,
            "hasSecrets": advice.hasFindings,
        ]
        if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]),
           let string = String(data: data, encoding: .utf8) {
            print(string)
        }
        if advice.hasFindings {
            throw ExitCode(OffsendExitCode.findings.rawValue)
        }
    }

    private func renderStdinReport(_ textResult: OffsendTextCheckResult) throws {
        let outputFormat = CLIParse.outputFormat(format)
        let useColor = CLIColor.enabled(for: outputFormat)
        let output = CheckReporter().render(
            textResult.report,
            format: outputFormat,
            quiet: quiet,
            verbose: verbose,
            useColor: useColor
        )
        if !output.isEmpty {
            print(output)
        }

        if textResult.report.shouldFail {
            throw ExitCode(OffsendExitCode.findings.rawValue)
        }
    }

    private func hookEmitter() -> CheckHookEmitter {
        CheckHookEmitter(
            quiet: quiet,
            debugHook: debugHook,
            notify: notify,
            secretsOnly: secretsOnly,
            sealCopy: sealCopy,
            keyFile: keyFile,
            keyName: keyName,
            workingDirectory: URL(
                fileURLWithPath: workingDirectory ?? FileManager.default.currentDirectoryPath
            ).standardizedFileURL
        )
    }

    private func resolvedHookPolicy(for adapter: CheckHookAdapter) -> CheckHookPolicy {
        if let hookPolicy {
            return CLIParse.checkHookPolicy(hookPolicy)
        }
        return CheckHookPolicy.defaultPolicy(for: adapter)
    }

    private func runFilePath() async throws {
        let outputFormat = CLIParse.outputFormat(format)
        let validatedFailOn = CLIParse.failPolicy(failOn)

        if adapter != nil || hookPolicy != nil || sealCopy || debugHook || gateSecrets || readGate || shellGate || mcpGate || subagentGate {
            CLIError.exit(
                .error,
                message: "--adapter/--hook-policy/--seal-copy/--debug-hook/--gate-secrets/--read-gate/--shell-gate/--mcp-gate/--subagent-gate require stdin."
            )
        }

        if staged, !paths.isEmpty {
            CLIError.exit(.error, message: "--staged cannot be combined with explicit paths.")
        }

        let context: OffsendRuntimeContext
        do {
            context = try OffsendRuntimeContext.load()
        } catch {
            CLIError.exit(.error, message: "Failed to load Offsend settings: \(error.localizedDescription)")
        }

        let workingURL = URL(
            fileURLWithPath: workingDirectory ?? FileManager.default.currentDirectoryPath
        ).standardizedFileURL

        let projectConfig = CLIParse.projectConfig(from: workingURL)
        let resolved = OptionsResolver.resolveCheckOptions(
            overrides: CLICheckOverrides(
                policySpecified: policy,
                policyValue: policy,
                failOn: validatedFailOn
            ),
            projectConfig: projectConfig,
            staged: staged
        )

        let gitResolver = GitRepositoryResolver()
        var fileURLs: [URL] = []
        var policyDirectoryURL: URL?
        var scanRoot = workingURL
        var stagedExportRoot: URL?
        defer {
            if let stagedExportRoot {
                try? FileManager.default.removeItem(at: stagedExportRoot)
            }
        }

        if staged {
            let repositoryRoot = resolveRepositoryRoot(startingAt: workingURL, gitResolver: gitResolver)
            let exportRoot = FileManager.default.temporaryDirectory
                .appendingPathComponent("offsend-staged-\(UUID().uuidString)", isDirectory: true)
            stagedExportRoot = exportRoot
            do {
                fileURLs = try gitResolver.exportStagedFiles(in: repositoryRoot, to: exportRoot)
            } catch let error as GitRepositoryError {
                try? FileManager.default.removeItem(at: exportRoot)
                CLIError.exit(for: error)
            } catch {
                try? FileManager.default.removeItem(at: exportRoot)
                CLIError.exit(.error, message: "Failed to read staged files: \(error.localizedDescription)")
            }
            scanRoot = exportRoot
            if resolved.policy {
                policyDirectoryURL = repositoryRoot
            }
        } else if !paths.isEmpty {
            var directoryURLs: [URL] = []
            for path in paths {
                let url = URL(fileURLWithPath: path, relativeTo: workingURL).standardizedFileURL
                var isDirectory: ObjCBool = false
                guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
                    CLIError.exit(.error, message: "Path not found: \(url.path)")
                }
                if isDirectory.boolValue {
                    directoryURLs.append(url)
                    fileURLs.append(
                        contentsOf: collectFiles(
                            in: url,
                            excludePatterns: resolved.excludePatterns,
                            relativeTo: workingURL
                        )
                    )
                } else {
                    fileURLs.append(url)
                }
            }
            if resolved.policy {
                if directoryURLs.count > 1 {
                    CLIError.exit(.error, message: "--policy supports a single directory; got \(directoryURLs.count).")
                }
                policyDirectoryURL = directoryURLs.first
                    ?? resolveRepositoryRoot(startingAt: workingURL, gitResolver: gitResolver)
            }
        } else if resolved.policy {
            policyDirectoryURL = resolveRepositoryRoot(startingAt: workingURL, gitResolver: gitResolver)
        } else {
            CLIError.exit(.error, message: "Provide file paths, --staged, --policy, or --stdin.")
        }

        let service = OffsendCheckService(context: context)
        let request = OffsendCheckRequest(
            fileURLs: fileURLs,
            policyDirectoryURL: policyDirectoryURL,
            failPolicy: resolved.failPolicy,
            workingDirectory: scanRoot,
            excludePatterns: resolved.excludePatterns,
            disabledDetectors: resolved.disabledDetectors,
            customDictionaries: resolved.customDictionaries
        )
        let report = await CLISpinner(message: "Scanning...").runWhile {
            await service.run(request)
        }

        let useColor = CLIColor.enabled(for: outputFormat)
        let output = CheckReporter().render(report, format: outputFormat, quiet: quiet, verbose: verbose, useColor: useColor)
        if !output.isEmpty {
            print(output)
        }

        if report.hasErrors {
            throw ExitCode(OffsendExitCode.error.rawValue)
        }
        if report.shouldFail {
            throw ExitCode(OffsendExitCode.findings.rawValue)
        }
    }

    private func collectFiles(
        in directory: URL,
        excludePatterns: [String],
        relativeTo workingDirectory: URL
    ) -> [URL] {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isDirectoryKey]
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: Array(keys)
        ) else {
            return []
        }

        var files: [URL] = []
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: keys)
            if values?.isDirectory == true {
                let relative = PathExcludeMatcher.relativePath(of: url, relativeTo: workingDirectory)
                if PathExcludeMatcher.shouldSkipDirectory(relativePath: relative, patterns: excludePatterns) {
                    enumerator.skipDescendants()
                }
                continue
            }
            if values?.isRegularFile == true {
                files.append(url.standardizedFileURL)
            }
        }
        return files.sorted { $0.path < $1.path }
    }

    private func resolveRepositoryRoot(
        startingAt path: URL,
        gitResolver: GitRepositoryResolver
    ) -> URL {
        do {
            return try gitResolver.repositoryRoot(startingAt: path)
        } catch let error as GitRepositoryError {
            CLIError.exit(for: error)
        } catch {
            CLIError.exit(.error, message: error.localizedDescription)
        }
    }
}
