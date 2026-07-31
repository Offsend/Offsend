//! Sensitive-path allowlist — port of Swift `SensitivePathExposureAllowlist`.

use crate::glob::GlobPattern;

pub static DEFAULT_ALLOWLIST_PATTERNS: &[&str] = &[
    ".env.example",
    "**/.env.example",
    "public.key",
    "**/public.key",
    "license.key",
    "**/license.key",
    "licence.key",
    "**/licence.key",
    "Tests/**",
    "**/Tests/**",
    "test/**",
    "**/test/**",
    "**/*Tests/**",
    "**/*tests/**",
];

pub fn is_allowlisted(relative_path: &str, patterns: &[&str]) -> bool {
    patterns
        .iter()
        .any(|p| GlobPattern::new(p).matches(relative_path))
}

pub fn is_allowlisted_default(relative_path: &str) -> bool {
    is_allowlisted(relative_path, DEFAULT_ALLOWLIST_PATTERNS)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn allows_env_example_and_test_dirs() {
        assert!(is_allowlisted_default(".env.example"));
        assert!(is_allowlisted_default("pkg/.env.example"));
        assert!(is_allowlisted_default("public.key"));
        assert!(is_allowlisted_default("Tests/Fixtures/secret.pem"));
        assert!(!is_allowlisted_default(".env"));
        assert!(!is_allowlisted_default("server.pem"));
    }
}
