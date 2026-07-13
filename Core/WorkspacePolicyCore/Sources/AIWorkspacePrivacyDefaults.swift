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
            id: "aider-ignore",
            toolName: "Aider",
            title: ".aiderignore",
            relativePathPatterns: [".aiderignore"],
            severity: .recommended,
            scansForSensitivePatterns: true,
            remediation: "Add .aiderignore for Aider workspace exclusions.",
            fix: AIWorkspacePrivacyFileFix(
                relativePath: ".aiderignore",
                contents: AIWorkspacePrivacyIgnoreTemplate.contents
            )
        ),
        AIWorkspacePrivacyRule(
            id: "cline-ignore",
            toolName: "Cline",
            title: ".clineignore",
            relativePathPatterns: [".clineignore"],
            severity: .recommended,
            scansForSensitivePatterns: true,
            remediation: "Add .clineignore for Cline workspace exclusions.",
            fix: AIWorkspacePrivacyFileFix(
                relativePath: ".clineignore",
                contents: AIWorkspacePrivacyIgnoreTemplate.contents
            )
        ),
        AIWorkspacePrivacyRule(
            id: "roo-ignore",
            toolName: "Roo Code",
            title: ".rooignore",
            relativePathPatterns: [".rooignore"],
            severity: .recommended,
            scansForSensitivePatterns: true,
            remediation: "Add .rooignore for Roo Code workspace exclusions.",
            fix: AIWorkspacePrivacyFileFix(
                relativePath: ".rooignore",
                contents: AIWorkspacePrivacyIgnoreTemplate.contents
            )
        ),
        AIWorkspacePrivacyRule(
            id: "zed-ignore",
            toolName: "Zed",
            title: ".zedignore",
            relativePathPatterns: [".zedignore"],
            severity: .recommended,
            scansForSensitivePatterns: true,
            remediation: "Add .zedignore for Zed AI assistant exclusions.",
            fix: AIWorkspacePrivacyFileFix(
                relativePath: ".zedignore",
                contents: AIWorkspacePrivacyIgnoreTemplate.contents
            )
        ),
        AIWorkspacePrivacyRule(
            id: "cody-ignore",
            toolName: "Sourcegraph Cody",
            title: ".codyignore",
            relativePathPatterns: [".codyignore"],
            severity: .recommended,
            scansForSensitivePatterns: true,
            remediation: "Add .codyignore for Sourcegraph Cody workspace exclusions.",
            fix: AIWorkspacePrivacyFileFix(
                relativePath: ".codyignore",
                contents: AIWorkspacePrivacyIgnoreTemplate.contents
            )
        ),
        AIWorkspacePrivacyRule(
            id: "agents-md",
            toolName: "Codex / Agents",
            title: "AGENTS.md",
            relativePathPatterns: ["AGENTS.md"],
            severity: .informational,
            scansForSensitivePatterns: false,
            remediation: "Add AGENTS.md to describe how agentic tools should handle sensitive files."
        ),
        AIWorkspacePrivacyRule(
            id: "claude-md",
            toolName: "Claude Code",
            title: "CLAUDE.md",
            relativePathPatterns: ["CLAUDE.md"],
            severity: .informational,
            scansForSensitivePatterns: false,
            remediation: "Add CLAUDE.md to give Claude Code project-specific privacy guidance."
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
            category: .secret,
            remediation: "Ignore .env and .env.* files."
        ),
        AIWorkspaceSensitivePattern(
            id: "pem-files",
            title: "PEM keys",
            acceptedPatterns: ["*.pem", "**/*.pem"],
            severity: .required,
            category: .secret,
            remediation: "Ignore PEM key files."
        ),
        AIWorkspaceSensitivePattern(
            id: "key-files",
            title: "Key files",
            acceptedPatterns: ["*.key", "**/*.key"],
            severity: .required,
            category: .secret,
            remediation: "Ignore private key files."
        ),
        AIWorkspaceSensitivePattern(
            id: "ssh-files",
            title: "SSH material",
            acceptedPatterns: [
                ".ssh/",
                "**/.ssh/",
                "id_rsa",
                "**/id_rsa",
                "**/.ssh/id_rsa",
                "id_ed25519",
                "**/id_ed25519",
                "id_ecdsa",
                "**/id_ecdsa",
                "*.ppk",
                "**/*.ppk"
            ],
            severity: .recommended,
            category: .secret,
            remediation: "Ignore SSH directories and private key files (id_rsa, id_ed25519, id_ecdsa, *.ppk)."
        ),
        AIWorkspaceSensitivePattern(
            id: "aws-files",
            title: "AWS credentials",
            acceptedPatterns: [".aws/", "**/.aws/", ".aws/credentials", "**/.aws/credentials"],
            severity: .recommended,
            category: .cloud,
            remediation: "Ignore AWS credential directories and files."
        ),
        AIWorkspaceSensitivePattern(
            id: "credentials-json",
            title: "credentials.json",
            acceptedPatterns: ["credentials.json", "**/credentials.json"],
            severity: .required,
            category: .secret,
            remediation: "Ignore credentials.json files."
        ),
        AIWorkspaceSensitivePattern(
            id: "secrets-json",
            title: "secrets.json",
            acceptedPatterns: ["secrets.json", "**/secrets.json"],
            severity: .required,
            category: .secret,
            remediation: "Ignore secrets.json files."
        ),
        AIWorkspaceSensitivePattern(
            id: "gcp-credentials",
            title: "GCP service account keys",
            acceptedPatterns: [
                "service-account*.json",
                "**/service-account*.json",
                "gcp-credentials*.json",
                "**/gcp-credentials*.json"
            ],
            severity: .recommended,
            category: .cloud,
            remediation: "Ignore GCP service account JSON keys."
        ),
        AIWorkspaceSensitivePattern(
            id: "azure-credentials",
            title: "Azure credentials",
            acceptedPatterns: [
                ".azure/",
                "**/.azure/",
                "azureauth.json",
                "**/azureauth.json"
            ],
            severity: .recommended,
            category: .cloud,
            remediation: "Ignore Azure CLI credentials and tokens."
        ),
        AIWorkspaceSensitivePattern(
            id: "kube-config",
            title: "Kubernetes config",
            acceptedPatterns: [
                "kubeconfig",
                "**/kubeconfig",
                "*.kubeconfig",
                "**/*.kubeconfig",
                ".kube/",
                "**/.kube/"
            ],
            severity: .required,
            category: .cloud,
            remediation: "Ignore kubeconfig files that grant cluster access."
        ),
        AIWorkspaceSensitivePattern(
            id: "terraform-state",
            title: "Terraform state",
            acceptedPatterns: [
                "*.tfstate",
                "**/*.tfstate",
                "*.tfstate.*",
                "**/*.tfstate.*"
            ],
            severity: .recommended,
            category: .cloud,
            remediation: "Ignore Terraform state files that often embed secrets."
        ),
        AIWorkspaceSensitivePattern(
            id: "terraform-vars",
            title: "Terraform variables",
            acceptedPatterns: ["*.tfvars", "**/*.tfvars"],
            severity: .recommended,
            category: .cloud,
            remediation: "Ignore Terraform tfvars files that may hold credentials."
        ),
        AIWorkspaceSensitivePattern(
            id: "pkcs12-p12",
            title: "PKCS#12 (.p12) certificates",
            acceptedPatterns: ["*.p12", "**/*.p12"],
            severity: .recommended,
            category: .signing,
            remediation: "Ignore .p12 certificate bundles that contain private keys."
        ),
        AIWorkspaceSensitivePattern(
            id: "pkcs12-pfx",
            title: "PKCS#12 (.pfx) certificates",
            acceptedPatterns: ["*.pfx", "**/*.pfx"],
            severity: .recommended,
            category: .signing,
            remediation: "Ignore .pfx certificate bundles that contain private keys."
        ),
        AIWorkspaceSensitivePattern(
            id: "pgp-keys",
            title: "PGP private keys",
            acceptedPatterns: [
                "*.gpg",
                "**/*.gpg",
                "secring.*",
                "**/secring.*"
            ],
            severity: .recommended,
            category: .secret,
            remediation: "Ignore PGP/GnuPG private keyrings."
        ),
        AIWorkspaceSensitivePattern(
            id: "netrc-files",
            title: ".netrc",
            acceptedPatterns: [
                ".netrc",
                "**/.netrc",
                "_netrc",
                "**/_netrc"
            ],
            severity: .recommended,
            category: .secret,
            remediation: "Ignore .netrc / _netrc files that store HTTP credentials."
        ),
        AIWorkspaceSensitivePattern(
            id: "npmrc-files",
            title: ".npmrc",
            acceptedPatterns: [".npmrc", "**/.npmrc"],
            severity: .recommended,
            category: .secret,
            remediation: "Ignore .npmrc — it commonly contains npm auth tokens."
        ),
        AIWorkspaceSensitivePattern(
            id: "pypirc-files",
            title: ".pypirc",
            acceptedPatterns: [".pypirc", "**/.pypirc"],
            severity: .recommended,
            category: .secret,
            remediation: "Ignore .pypirc — it commonly contains PyPI upload tokens."
        ),
        AIWorkspaceSensitivePattern(
            id: "htpasswd-files",
            title: ".htpasswd",
            acceptedPatterns: [".htpasswd", "**/.htpasswd"],
            severity: .recommended,
            category: .secret,
            remediation: "Ignore .htpasswd files containing hashed credentials."
        ),
        AIWorkspaceSensitivePattern(
            id: "docker-config",
            title: "Docker config",
            acceptedPatterns: [
                ".docker/",
                "**/.docker/",
                ".dockerconfigjson",
                "**/.dockerconfigjson"
            ],
            severity: .recommended,
            category: .secret,
            remediation: "Ignore Docker config that stores registry auth tokens."
        ),
        AIWorkspaceSensitivePattern(
            id: "firebase-keys",
            title: "Firebase admin keys",
            acceptedPatterns: [
                "serviceAccountKey.json",
                "**/serviceAccountKey.json",
                "firebase-adminsdk-*.json",
                "**/firebase-adminsdk-*.json"
            ],
            severity: .required,
            category: .cloud,
            remediation: "Ignore Firebase Admin SDK JSON keys."
        ),
        AIWorkspaceSensitivePattern(
            id: "firebase-client-config",
            title: "Firebase client config",
            acceptedPatterns: [
                "google-services.json",
                "**/google-services.json",
                "GoogleService-Info.plist",
                "**/GoogleService-Info.plist"
            ],
            severity: .recommended,
            category: .cloud,
            remediation: "Ignore google-services.json / GoogleService-Info.plist — they embed API keys."
        ),
        AIWorkspaceSensitivePattern(
            id: "android-local-properties",
            title: "Android local.properties",
            acceptedPatterns: ["local.properties", "**/local.properties"],
            severity: .recommended,
            category: .secret,
            remediation: "Ignore local.properties — it can hold SDK paths and signing secrets."
        ),
        AIWorkspaceSensitivePattern(
            id: "xcode-secrets-xcconfig",
            title: "Xcode Secrets.xcconfig",
            acceptedPatterns: ["Secrets.xcconfig", "**/Secrets.xcconfig"],
            severity: .recommended,
            category: .secret,
            remediation: "Ignore Secrets.xcconfig files that typically hold API keys."
        ),
        AIWorkspaceSensitivePattern(
            id: "spring-local-config",
            title: "Spring application-local config",
            acceptedPatterns: [
                "application-local.*",
                "**/application-local.*"
            ],
            severity: .recommended,
            category: .secret,
            remediation: "Ignore application-local.* — local Spring profiles often embed credentials."
        ),
        AIWorkspaceSensitivePattern(
            id: "cargo-credentials",
            title: "Cargo credentials",
            acceptedPatterns: [
                ".cargo/credentials",
                "**/.cargo/credentials",
                ".cargo/credentials.toml",
                "**/.cargo/credentials.toml",
                ".cargo/credentials.json",
                "**/.cargo/credentials.json",
                ".cargo/credentials*",
                "**/.cargo/credentials*"
            ],
            severity: .recommended,
            category: .secret,
            remediation: "Ignore Cargo credentials files that store crates.io tokens."
        ),
        AIWorkspaceSensitivePattern(
            id: "auth-json",
            title: "auth.json",
            acceptedPatterns: ["auth.json", "**/auth.json"],
            severity: .recommended,
            category: .secret,
            remediation: "Ignore auth.json (Composer and similar tools store tokens there)."
        ),
        AIWorkspaceSensitivePattern(
            id: "aws-root-key-csv",
            title: "AWS access key CSV",
            acceptedPatterns: [
                "accessKeys.csv",
                "**/accessKeys.csv",
                "credentials.csv",
                "**/credentials.csv"
            ],
            severity: .required,
            category: .cloud,
            remediation: "Ignore AWS access key CSV downloads (accessKeys.csv / credentials.csv)."
        ),
        AIWorkspaceSensitivePattern(
            id: "vpn-rdp-configs",
            title: "VPN / RDP configs",
            acceptedPatterns: ["*.ovpn", "**/*.ovpn", "*.rdp", "**/*.rdp"],
            severity: .recommended,
            category: .secret,
            remediation: "Ignore .ovpn / .rdp files — they often embed passwords or private keys."
        ),
        AIWorkspaceSensitivePattern(
            id: "keepass-databases",
            title: "KeePass databases",
            acceptedPatterns: ["*.kdbx", "**/*.kdbx"],
            severity: .required,
            category: .secret,
            remediation: "Ignore KeePass databases (.kdbx)."
        ),
        AIWorkspaceSensitivePattern(
            id: "fly-cli-config",
            title: "Fly.io CLI config",
            acceptedPatterns: [".fly/", "**/.fly/", ".fly/config.yml", "**/.fly/config.yml"],
            severity: .recommended,
            category: .cloud,
            remediation: "Ignore .fly/ — Fly CLI config can contain access tokens."
        ),
        AIWorkspaceSensitivePattern(
            id: "git-credentials",
            title: "Git credentials",
            acceptedPatterns: [".git-credentials", "**/.git-credentials"],
            severity: .required,
            category: .secret,
            remediation: "Ignore .git-credentials — it stores plaintext Git tokens."
        ),
        AIWorkspaceSensitivePattern(
            id: "pgpass-files",
            title: ".pgpass",
            acceptedPatterns: [".pgpass", "**/.pgpass"],
            severity: .recommended,
            category: .secret,
            remediation: "Ignore .pgpass — it stores PostgreSQL connection passwords."
        ),
        AIWorkspaceSensitivePattern(
            id: "mysql-client-config",
            title: ".my.cnf",
            acceptedPatterns: [".my.cnf", "**/.my.cnf"],
            severity: .recommended,
            category: .secret,
            remediation: "Ignore .my.cnf — it commonly stores MySQL client passwords."
        ),
        AIWorkspaceSensitivePattern(
            id: "yarn-config",
            title: ".yarnrc.yml",
            acceptedPatterns: [".yarnrc.yml", "**/.yarnrc.yml"],
            severity: .recommended,
            category: .secret,
            remediation: "Ignore .yarnrc.yml — it can contain npmAuthToken values."
        ),
        AIWorkspaceSensitivePattern(
            id: "terraform-rc",
            title: "Terraform CLI config",
            acceptedPatterns: [".terraformrc", "**/.terraformrc", "terraform.rc", "**/terraform.rc"],
            severity: .recommended,
            category: .cloud,
            remediation: "Ignore .terraformrc / terraform.rc — they can hold cloud tokens."
        ),
        AIWorkspaceSensitivePattern(
            id: "apple-p8-keys",
            title: "Apple .p8 keys",
            acceptedPatterns: ["*.p8", "**/*.p8"],
            severity: .recommended,
            category: .signing,
            remediation: "Ignore .p8 keys (App Store Connect / APNs private keys)."
        ),
        AIWorkspaceSensitivePattern(
            id: "android-keystore",
            title: "Android keystore",
            acceptedPatterns: ["*.keystore", "**/*.keystore", "*.jks", "**/*.jks"],
            severity: .recommended,
            category: .signing,
            remediation: "Ignore Android signing keystores (.keystore / .jks)."
        ),
        AIWorkspaceSensitivePattern(
            id: "apple-provisioning",
            title: "Apple provisioning profiles",
            acceptedPatterns: ["*.mobileprovision", "**/*.mobileprovision"],
            severity: .recommended,
            category: .signing,
            remediation: "Ignore .mobileprovision provisioning profiles."
        ),
        AIWorkspaceSensitivePattern(
            id: "local-databases",
            title: "Local databases",
            acceptedPatterns: [
                "*.sqlite",
                "**/*.sqlite",
                "*.sqlite3",
                "**/*.sqlite3"
            ],
            severity: .informational,
            category: .pii,
            remediation: "Consider ignoring local SQLite databases (.sqlite/.sqlite3) which often hold PII."
        ),
        AIWorkspaceSensitivePattern(
            id: "log-files",
            title: "Log files",
            acceptedPatterns: ["*.log", "**/*.log", "logs/", "**/logs/"],
            severity: .informational,
            category: .pii,
            remediation: "Consider ignoring logs/ and *.log which can leak tokens and PII."
        ),
        AIWorkspaceSensitivePattern(
            id: "data-exports",
            title: "Data exports & dumps",
            acceptedPatterns: ["dumps/", "**/dumps/", "exports/", "**/exports/"],
            severity: .informational,
            category: .pii,
            remediation: "Consider ignoring dumps/ and exports/ which often contain PII."
        ),
        AIWorkspaceSensitivePattern(
            id: "backup-files",
            title: "Backup files",
            acceptedPatterns: ["*.bak", "**/*.bak", "*.backup", "**/*.backup"],
            severity: .informational,
            category: .pii,
            remediation: "Consider ignoring *.bak / *.backup files that may contain sensitive snapshots."
        ),
        AIWorkspaceSensitivePattern(
            id: "shell-history",
            title: "Shell & REPL history",
            acceptedPatterns: [
                ".bash_history",
                "**/.bash_history",
                ".zsh_history",
                "**/.zsh_history",
                ".psql_history",
                "**/.psql_history",
                ".mysql_history",
                "**/.mysql_history",
                ".python_history",
                "**/.python_history"
            ],
            severity: .informational,
            category: .history,
            remediation: "Consider ignoring shell/REPL history files that can capture secrets."
        ),
        AIWorkspaceSensitivePattern(
            id: "db-dumps",
            title: "Database dumps",
            acceptedPatterns: [
                "*.sql.gz",
                "**/*.sql.gz",
                "*.dump",
                "**/*.dump"
            ],
            severity: .informational,
            category: .pii,
            remediation: "Consider ignoring database dumps which often contain PII."
        )
    ]
}
