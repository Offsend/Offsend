//! Default AI-ignore template — port of Swift `AIWorkspacePrivacyIgnoreTemplate`.

pub const IGNORE_TEMPLATE_HEADER: &str = "# Offsend AI privacy defaults";

pub const PRIVACY_RULE_TEXT: &str = "Keep secrets, credentials, private keys, and environment files out of AI context. Respect .cursorignore and other AI ignore files before reading or summarizing project contents.";

pub const MANAGED_RULE_HEADER: &str =
    "<!-- Managed by Offsend. Do not edit: changes are overwritten on sync. Add your own rules in a separate file. -->";

/// Default AI-ignore patterns seeded into `ignore.patterns` / editor ignore files.
pub static DEFAULT_IGNORE_PATTERNS: &[&str] = &[
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
    "_netrc",
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
    "secring.*",
    ".gnupg/",
    "master.key",
    "secrets.yml",
    "secrets.yaml",
    "credentials.yml",
    "credentials.yaml",
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
    "*.dump",
];

pub fn managed_seed_contents() -> String {
    format!("{IGNORE_TEMPLATE_HEADER}\n")
}

pub fn ignore_template_contents() -> String {
    let mut lines = vec![IGNORE_TEMPLATE_HEADER.to_string()];
    lines.extend(DEFAULT_IGNORE_PATTERNS.iter().map(|s| (*s).to_string()));
    lines.join("\n") + "\n"
}

pub fn cursor_privacy_rule_contents() -> String {
    format!(
        "---\nalwaysApply: true\n---\n{MANAGED_RULE_HEADER}\n{PRIVACY_RULE_TEXT}\n"
    )
}

pub fn claude_privacy_rule_contents() -> String {
    format!("{MANAGED_RULE_HEADER}\n{PRIVACY_RULE_TEXT}\n")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn template_has_header_and_env() {
        let c = ignore_template_contents();
        assert!(c.starts_with(IGNORE_TEMPLATE_HEADER));
        assert!(c.contains(".env*"));
        assert!(c.contains("*.pem"));
        assert!(c.ends_with('\n'));
    }
}
