//! Resolve audit configuration from defaults + `.offsend.yml` + app overrides.

use crate::audit_model::{AuditConfiguration, FixStrategy, RuleSeverity};
use crate::config::OffsendProjectConfig;
use crate::defaults::default_audit_configuration;
use std::collections::HashSet;
use std::path::Path;

/// Optional overrides from the macOS app / FFI callers.
#[derive(Debug, Clone)]
pub struct AuditConfigOverrides {
    /// Non-required rule IDs to drop (required rules are never removed).
    pub disabled_rule_ids: HashSet<String>,
    pub additional_skipped_directory_names: HashSet<String>,
    /// When set, replaces ignore-file fix contents (not managed editor rule files).
    pub custom_ignore_template: Option<String>,
    /// When true (default), apply `ignore.tools` filtering from `.offsend.yml`.
    pub load_project_config: bool,
}

impl Default for AuditConfigOverrides {
    fn default() -> Self {
        Self {
            disabled_rule_ids: HashSet::new(),
            additional_skipped_directory_names: HashSet::new(),
            custom_ignore_template: None,
            load_project_config: true,
        }
    }
}

impl AuditConfigOverrides {
    pub fn new() -> Self {
        Self::default()
    }
}

/// Build an [`AuditConfiguration`] for `directory` using defaults, optional project
/// config, and app overrides (disabled rules, skipped dirs, custom ignore template).
pub fn resolve_audit_configuration(
    directory: &Path,
    overrides: &AuditConfigOverrides,
) -> AuditConfiguration {
    let mut configuration = default_audit_configuration();

    if overrides.load_project_config {
        if let Ok(Some((_, cfg))) = OffsendProjectConfig::find_and_load(directory) {
            if let Some(ignore) = cfg.ignore.as_ref() {
                if let Some(tools) = ignore.tool_ids() {
                    configuration = configuration.filtered(Some(&tools));
                }
            }
        }
    }

    if !overrides.disabled_rule_ids.is_empty() {
        configuration.rules.retain(|rule| {
            rule.severity == RuleSeverity::Required
                || !overrides.disabled_rule_ids.contains(&rule.id)
        });
    }

    if let Some(template) = overrides
        .custom_ignore_template
        .as_ref()
        .map(|s| s.trim())
        .filter(|s| !s.is_empty())
    {
        for rule in &mut configuration.rules {
            let Some(fix) = rule.fix.as_mut() else {
                continue;
            };
            if fix.strategy == FixStrategy::KeepManagedContent {
                continue;
            }
            fix.contents = template.to_string();
        }
    }

    configuration
        .additional_skipped_directory_names
        .extend(overrides.additional_skipped_directory_names.iter().cloned());

    configuration
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;

    #[test]
    fn disables_non_required_rules() {
        let dir = tempfile_dir();
        let mut overrides = AuditConfigOverrides::new();
        overrides.disabled_rule_ids.insert("claude-ignore".into());
        let cfg = resolve_audit_configuration(&dir, &overrides);
        assert!(!cfg.rules.iter().any(|r| r.id == "claude-ignore"));
        assert!(cfg.rules.iter().any(|r| r.id == "cursor-ignore")); // required
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn applies_custom_ignore_template() {
        let dir = tempfile_dir();
        let mut overrides = AuditConfigOverrides::new();
        overrides.custom_ignore_template = Some("custom-pattern\n".into());
        let cfg = resolve_audit_configuration(&dir, &overrides);
        let cursor = cfg.rules.iter().find(|r| r.id == "cursor-ignore").unwrap();
        assert_eq!(cursor.fix.as_ref().unwrap().contents, "custom-pattern");
        let _ = fs::remove_dir_all(&dir);
    }

    fn tempfile_dir() -> std::path::PathBuf {
        let dir = std::env::temp_dir().join(format!(
            "offsend-audit-config-{}",
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        fs::create_dir_all(&dir).unwrap();
        dir
    }
}
