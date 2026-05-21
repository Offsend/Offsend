private enum AIWorkspacePrivacyDefaultFixes {
    static let cursorPrivacyRuleContents = """
    ---
    alwaysApply: true
    ---
    Keep secrets, credentials, private keys, and environment files out of AI context. Respect .cursorignore and other AI ignore files before reading or summarizing project contents.
    """
}

public extension AIWorkspacePrivacyRule {
    static let defaultRules: [AIWorkspacePrivacyRule] = [
        AIWorkspacePrivacyRule(
            id: "cursor-ignore",
            toolName: "Cursor",
            title: ".cursorignore",
            relativePathPatterns: [".cursorignore"],
            severity: .required,
            scansForSensitivePatterns: true,
            remediation: "Add .cursorignore with sensitive file patterns such as .env*, *.pem, *.key, credentials.json, and secrets.json.",
            fix: AIWorkspacePrivacyFileFix(
                relativePath: ".cursorignore",
                contents: AIWorkspacePrivacyIgnoreTemplate.contents
            )
        ),
        AIWorkspacePrivacyRule(
            id: "cursor-indexing-ignore",
            toolName: "Cursor",
            title: ".cursorindexingignore",
            relativePathPatterns: [".cursorindexingignore"],
            severity: .informational,
            scansForSensitivePatterns: false,
            remediation: "Add .cursorindexingignore if you also want to exclude files from Cursor indexing.",
            fix: AIWorkspacePrivacyFileFix(
                relativePath: ".cursorindexingignore",
                contents: AIWorkspacePrivacyIgnoreTemplate.contents
            )
        ),
        AIWorkspacePrivacyRule(
            id: "cursor-project-rules",
            toolName: "Cursor",
            title: ".cursor/rules",
            relativePathPatterns: [".cursor/rules/*.md", ".cursor/rules/*.mdc"],
            severity: .recommended,
            scansForSensitivePatterns: false,
            remediation: "Add .cursor/rules/*.mdc project rules that describe how AI tools should handle sensitive files.",
            fix: AIWorkspacePrivacyFileFix(
                relativePath: ".cursor/rules/privacy.mdc",
                contents: AIWorkspacePrivacyDefaultFixes.cursorPrivacyRuleContents,
                strategy: .createIfMissing
            )
        ),
        AIWorkspacePrivacyRule(
            id: "copilot-exclude",
            toolName: "GitHub Copilot",
            title: ".aiexclude",
            relativePathPatterns: [".aiexclude"],
            severity: .recommended,
            scansForSensitivePatterns: true,
            remediation: "Add .aiexclude for GitHub Copilot-style exclusion patterns.",
            fix: AIWorkspacePrivacyFileFix(
                relativePath: ".aiexclude",
                contents: AIWorkspacePrivacyIgnoreTemplate.contents
            )
        ),
        AIWorkspacePrivacyRule(
            id: "continue-ignore",
            toolName: "Continue",
            title: ".continueignore",
            relativePathPatterns: [".continueignore"],
            severity: .recommended,
            scansForSensitivePatterns: true,
            remediation: "Add .continueignore for Continue workspace exclusions.",
            fix: AIWorkspacePrivacyFileFix(
                relativePath: ".continueignore",
                contents: AIWorkspacePrivacyIgnoreTemplate.contents
            )
        ),
        AIWorkspacePrivacyRule(
            id: "codeium-ignore",
            toolName: "Windsurf / Codeium",
            title: ".codeiumignore",
            relativePathPatterns: [".codeiumignore"],
            severity: .recommended,
            scansForSensitivePatterns: true,
            remediation: "Add .codeiumignore for Windsurf and Codeium workspace exclusions.",
            fix: AIWorkspacePrivacyFileFix(
                relativePath: ".codeiumignore",
                contents: AIWorkspacePrivacyIgnoreTemplate.contents
            )
        ),
        AIWorkspacePrivacyRule(
            id: "claude-ignore",
            toolName: "Claude Code",
            title: ".claudeignore",
            relativePathPatterns: [".claudeignore"],
            severity: .recommended,
            scansForSensitivePatterns: true,
            remediation: "Add .claudeignore for Claude Code workspace exclusions.",
            fix: AIWorkspacePrivacyFileFix(
                relativePath: ".claudeignore",
                contents: AIWorkspacePrivacyIgnoreTemplate.contents
            )
        ),
        AIWorkspacePrivacyRule(
            id: "gemini-ignore",
            toolName: "Gemini Code Assist",
            title: ".geminiignore",
            relativePathPatterns: [".geminiignore"],
            severity: .recommended,
            scansForSensitivePatterns: true,
            remediation: "Add .geminiignore for Gemini Code Assist workspace exclusions.",
            fix: AIWorkspacePrivacyFileFix(
                relativePath: ".geminiignore",
                contents: AIWorkspacePrivacyIgnoreTemplate.contents
            )
        ),
        AIWorkspacePrivacyRule(
            id: "llm-ignore",
            toolName: "LLM tools",
            title: ".llmignore",
            relativePathPatterns: [".llmignore"],
            severity: .recommended,
            scansForSensitivePatterns: true,
            remediation: "Add .llmignore as a shared, tool-agnostic policy file where supported.",
            fix: AIWorkspacePrivacyFileFix(
                relativePath: ".llmignore",
                contents: AIWorkspacePrivacyIgnoreTemplate.contents
            )
        ),
        AIWorkspacePrivacyRule(
            id: "git-ignore",
            toolName: "Git",
            title: ".gitignore",
            relativePathPatterns: [".gitignore"],
            severity: .informational,
            scansForSensitivePatterns: false,
            remediation: ".gitignore is useful, but it should not be treated as the only AI privacy boundary."
        )
    ]
}

public extension AIWorkspaceSensitivePattern {
    static let defaultPatterns: [AIWorkspaceSensitivePattern] = [
        AIWorkspaceSensitivePattern(
            id: "env-files",
            title: "Environment files",
            acceptedPatterns: [".env", ".env.*", ".env*", "**/.env", "**/.env.*", "**/.env*"],
            severity: .required,
            remediation: "Ignore .env and .env.* files."
        ),
        AIWorkspaceSensitivePattern(
            id: "pem-files",
            title: "PEM keys",
            acceptedPatterns: ["*.pem", "**/*.pem"],
            severity: .required,
            remediation: "Ignore PEM key files."
        ),
        AIWorkspaceSensitivePattern(
            id: "key-files",
            title: "Key files",
            acceptedPatterns: ["*.key", "**/*.key"],
            severity: .required,
            remediation: "Ignore private key files."
        ),
        AIWorkspaceSensitivePattern(
            id: "ssh-files",
            title: "SSH material",
            acceptedPatterns: [".ssh/", "**/.ssh/", "id_rsa", "**/id_rsa", "**/.ssh/id_rsa"],
            severity: .recommended,
            remediation: "Ignore SSH directories and id_rsa files."
        ),
        AIWorkspaceSensitivePattern(
            id: "aws-files",
            title: "AWS credentials",
            acceptedPatterns: [".aws/", "**/.aws/", ".aws/credentials", "**/.aws/credentials"],
            severity: .recommended,
            remediation: "Ignore AWS credential directories and files."
        ),
        AIWorkspaceSensitivePattern(
            id: "credentials-json",
            title: "credentials.json",
            acceptedPatterns: ["credentials.json", "**/credentials.json"],
            severity: .required,
            remediation: "Ignore credentials.json files."
        ),
        AIWorkspaceSensitivePattern(
            id: "secrets-json",
            title: "secrets.json",
            acceptedPatterns: ["secrets.json", "**/secrets.json"],
            severity: .required,
            remediation: "Ignore secrets.json files."
        )
    ]
}
