import Foundation

public enum AIWorkspacePrivacyIgnoreTemplate {
    public static let header = "# Offsend AI privacy defaults"

    /// Default AI-ignore patterns. Seeded into `.offsend.yml` `ignore.patterns` by
    /// `offsend init`, then materialized into editor ignore files by `offsend sync`.
    public static let defaultPatterns: [String] = [
        ".env*",
        "*.pem",
        "*.key",
        ".ssh/",
        "id_rsa",
        "id_ed25519",
        "id_ecdsa",
        "*.ppk",
        ".aws/",
        ".azure/",
        ".kube/",
        ".docker/",
        ".cargo/credentials*",
        ".fly/",
        "credentials.json",
        "secrets.json",
        "auth.json",
        "service-account*.json",
        "gcp-credentials*.json",
        "azureauth.json",
        "kubeconfig",
        "*.kubeconfig",
        "*.tfstate",
        "*.tfstate.*",
        "*.tfvars",
        "*.p12",
        "*.pfx",
        "*.gpg",
        ".netrc",
        ".npmrc",
        ".pypirc",
        ".htpasswd",
        ".dockerconfigjson",
        "serviceAccountKey.json",
        "firebase-adminsdk-*.json",
        "google-services.json",
        "GoogleService-Info.plist",
        "local.properties",
        "Secrets.xcconfig",
        "application-local.*",
        "accessKeys.csv",
        "credentials.csv",
        "*.ovpn",
        "*.rdp",
        "*.kdbx",
        ".git-credentials",
        ".pgpass",
        ".my.cnf",
        ".yarnrc.yml",
        ".terraformrc",
        "terraform.rc",
        "*.p8",
        "*.keystore",
        "*.jks",
        "*.mobileprovision",
        "*.sqlite",
        "*.sqlite3",
        "*.log",
        "logs/",
        "dumps/",
        "exports/",
        "*.bak",
        "*.backup",
        ".bash_history",
        ".zsh_history",
        ".psql_history",
        ".mysql_history",
        ".python_history",
        "agent-transcripts/",
        "**/agent-transcripts/**",
        "*.sql.gz",
        "*.dump"
    ]

    /// Header-only seed when patterns come from `ignore.patterns` (managed block).
    public static var managedSeedContents: String {
        header + "\n"
    }

    /// Full plain-line template (header + defaults). Used when there is no project
    /// config / empty `ignore.patterns`. Prefer managed seed + sync when config exists.
    public static var contents: String {
        ([header] + defaultPatterns).joined(separator: "\n") + "\n"
    }
}
