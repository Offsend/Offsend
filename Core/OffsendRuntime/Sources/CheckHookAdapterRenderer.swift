import Foundation

public struct CheckHookAdapterOutput: Equatable, Sendable {
    public let stdout: String
    public let stderr: String
    public let exitCode: Int32

    public init(stdout: String, stderr: String = "", exitCode: Int32 = 0) {
        self.stdout = stdout
        self.stderr = stderr
        self.exitCode = exitCode
    }
}

/// Maps prompt-check advice into AI-editor hook response payloads.
public enum CheckHookAdapterRenderer {
    /// Allow the prompt through after an infrastructure error (parse/settings/size).
    /// `reason` is a short public code (see `FailOpenReason.code`); details go to debug log only.
    public static func failOpen(
        adapter: CheckHookAdapter,
        reason: String
    ) -> CheckHookAdapterOutput {
        CheckHookResponseRenderer.failOpen(
            adapter: adapter,
            reason: reason,
            kind: .promptSubmit
        )
    }

    public static func render(
        result: PromptCheckAdviceResult,
        adapter: CheckHookAdapter
    ) -> CheckHookAdapterOutput {
        let details = PromptCheckAdviceBuilder.detailLines(for: result)
        let combinedMessage = combinedUserMessage(result: result, details: details)
        let stderr: String
        if result.hasFindings {
            stderr = ([result.userMessage] + details).joined(separator: "\n") + "\n"
        } else {
            stderr = ""
        }

        switch adapter {
        case .cursor:
            return renderCursor(result: result, message: combinedMessage, stderr: stderr)
        case .claude, .codex:
            return renderClaudeFamily(result: result, message: combinedMessage, stderr: stderr)
        case .windsurf:
            return renderWindsurf(result: result, message: combinedMessage, stderr: stderr)
        }
    }

    private static func renderCursor(
        result: PromptCheckAdviceResult,
        message: String,
        stderr: String
    ) -> CheckHookAdapterOutput {
        switch result.policy {
        case .advise:
            return CheckHookAdapterOutput(
                stdout: jsonObject(["continue": true]),
                stderr: stderr,
                exitCode: 0
            )
        case .softBlock, .block:
            if result.hasFindings {
                return CheckHookAdapterOutput(
                    stdout: jsonObject([
                        "continue": false,
                        "user_message": message,
                    ]),
                    stderr: stderr,
                    exitCode: 0
                )
            }
            return CheckHookAdapterOutput(
                stdout: jsonObject(["continue": true]),
                stderr: "",
                exitCode: 0
            )
        }
    }

    private static func renderClaudeFamily(
        result: PromptCheckAdviceResult,
        message: String,
        stderr: String
    ) -> CheckHookAdapterOutput {
        switch result.policy {
        case .advise:
            if result.hasFindings {
                return CheckHookAdapterOutput(
                    stdout: jsonObject(["systemMessage": message]),
                    stderr: stderr,
                    exitCode: 0
                )
            }
            return CheckHookAdapterOutput(stdout: "{}", stderr: "", exitCode: 0)
        case .softBlock, .block:
            if result.hasFindings {
                return CheckHookAdapterOutput(
                    stdout: jsonObject([
                        "decision": "block",
                        "reason": message,
                        "systemMessage": message,
                    ]),
                    stderr: stderr,
                    exitCode: 0
                )
            }
            return CheckHookAdapterOutput(stdout: "{}", stderr: "", exitCode: 0)
        }
    }

    private static func renderWindsurf(
        result: PromptCheckAdviceResult,
        message: String,
        stderr: String
    ) -> CheckHookAdapterOutput {
        switch result.policy {
        case .advise:
            return CheckHookAdapterOutput(stdout: "", stderr: stderr, exitCode: 0)
        case .softBlock, .block:
            if result.hasFindings {
                return CheckHookAdapterOutput(
                    stdout: "",
                    stderr: message + "\n",
                    exitCode: OffsendExitCode.error.rawValue
                )
            }
            return CheckHookAdapterOutput(stdout: "", stderr: "", exitCode: 0)
        }
    }

    private static func combinedUserMessage(result: PromptCheckAdviceResult, details: [String]) -> String {
        guard result.hasFindings else { return result.userMessage }
        let bullets = details.prefix(5).map { "• \($0)" }.joined(separator: "\n")
        let more = details.count > 5 ? "\n• …and \(details.count - 5) more" : ""
        return result.userMessage + "\n" + bullets + more
    }

    private static func jsonObject(_ object: [String: Any]) -> String {
        CheckHookResponseRenderer.encodeJSONObject(object)
    }
}
