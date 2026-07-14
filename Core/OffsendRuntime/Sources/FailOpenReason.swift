import Foundation

/// Public fail-open codes for AI-editor hooks. Details stay in `--debug-hook` only.
public struct FailOpenReason: Equatable, Sendable {
    public let code: String
    public let debugDetail: String

    public init(code: String, debugDetail: String) {
        self.code = code
        self.debugDetail = debugDetail
    }

    public static let invalidJSON = FailOpenReason(
        code: "invalid_json",
        debugDetail: "Hook stdin is not valid JSON."
    )

    public static let invalidUTF8 = FailOpenReason(
        code: "invalid_utf8",
        debugDetail: "stdin is not valid UTF-8."
    )

    public static let stdinTooLarge = FailOpenReason(
        code: "stdin_too_large",
        debugDetail: "stdin exceeds \(CheckHookLimits.maxStdinBytes) bytes."
    )

    public static let stdinUnavailable = FailOpenReason(
        code: "stdin_unavailable",
        debugDetail: "Provide prompt text or hook JSON on stdin."
    )

    public static let stdinReadFailed = FailOpenReason(
        code: "stdin_read_failed",
        debugDetail: "Failed to read stdin."
    )

    public static func settingsUnavailable(_ detail: String) -> FailOpenReason {
        FailOpenReason(code: "settings_unavailable", debugDetail: detail)
    }

    public static func projectConfigInvalid(_ detail: String) -> FailOpenReason {
        FailOpenReason(code: "project_config_invalid", debugDetail: detail)
    }

    public static func missingPrompt(adapter: CheckHookAdapter) -> FailOpenReason {
        FailOpenReason(
            code: "missing_prompt",
            debugDetail: "Hook JSON is missing the prompt field for adapter '\(adapter.rawValue)'."
        )
    }

    public static func invalidHookPolicy(_ value: String) -> FailOpenReason {
        FailOpenReason(
            code: "invalid_hook_policy",
            debugDetail: "Invalid --hook-policy value: \(value). Expected advise, soft-block, or block."
        )
    }

    public static func fromPromptHookInputError(_ error: PromptHookInputError) -> FailOpenReason {
        switch error {
        case .invalidJSON:
            return .invalidJSON
        case .missingPrompt(let adapter):
            return .missingPrompt(adapter: adapter)
        }
    }
}
