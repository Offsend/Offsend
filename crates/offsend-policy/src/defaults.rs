//! Built-in audit defaults — rules + sensitive patterns from Swift
//! `AIWorkspacePrivacyDefaults` (loaded from JSON corpus).

use crate::audit_model::{
    AuditConfiguration, ExposureScanLimits, FileFix, FixStrategy, PrivacyRule, RuleSeverity,
    SensitiveCategory, SensitivePattern,
};
use crate::config::ToolId;
use crate::template::{
    claude_privacy_rule_contents, cursor_privacy_rule_contents, ignore_template_contents,
};
use once_cell::sync::Lazy;
use serde::Deserialize;

#[derive(Deserialize)]
struct RuleRow {
    id: String,
    tool_name: String,
    tool: Option<String>,
    title: String,
    relative_path_patterns: Vec<String>,
    severity: String,
    scans_for_sensitive_patterns: bool,
    remediation: String,
    fix_relative_path: Option<String>,
    fix_strategy: Option<String>,
}

#[derive(Deserialize)]
struct PatternRow {
    id: String,
    title: String,
    accepted_patterns: Vec<String>,
    severity: String,
    category: String,
    remediation: String,
}

pub static DEFAULT_SENSITIVE_PATTERNS: Lazy<Vec<SensitivePattern>> = Lazy::new(|| {
    let rows: Vec<PatternRow> =
        serde_json::from_str(include_str!("../data/default_sensitive_patterns.json"))
            .expect("default_sensitive_patterns.json");
    rows.into_iter()
        .filter(|r| !r.accepted_patterns.is_empty())
        .map(|r| SensitivePattern {
            id: r.id,
            title: r.title,
            accepted_patterns: r.accepted_patterns,
            severity: RuleSeverity::parse(&r.severity),
            category: SensitiveCategory::parse(&r.category),
            remediation: r.remediation,
        })
        .collect()
});

pub static DEFAULT_RULES: Lazy<Vec<PrivacyRule>> = Lazy::new(|| {
    let rows: Vec<RuleRow> =
        serde_json::from_str(include_str!("../data/default_rules.json")).expect("default_rules.json");
    rows.into_iter()
        .map(|r| {
            let fix = r.fix_relative_path.map(|path| {
                let strategy = FixStrategy::parse(r.fix_strategy.as_deref());
                let contents = fix_contents_for(&r.id, &path, strategy);
                FileFix {
                    relative_path: path,
                    contents,
                    strategy,
                }
            });
            PrivacyRule {
                id: r.id,
                tool_name: r.tool_name,
                tool: r.tool.as_deref().and_then(ToolId::parse),
                title: r.title,
                relative_path_patterns: r.relative_path_patterns,
                severity: RuleSeverity::parse(&r.severity),
                scans_for_sensitive_patterns: r.scans_for_sensitive_patterns,
                remediation: r.remediation,
                fix,
            }
        })
        .collect()
});

fn fix_contents_for(rule_id: &str, path: &str, strategy: FixStrategy) -> String {
    if strategy == FixStrategy::KeepManagedContent {
        if path.ends_with(".mdc") || rule_id.starts_with("cursor-project") {
            return cursor_privacy_rule_contents();
        }
        if path.ends_with(".md") || rule_id.starts_with("claude-project") {
            return claude_privacy_rule_contents();
        }
    }
    ignore_template_contents()
}

pub fn default_audit_configuration() -> AuditConfiguration {
    AuditConfiguration {
        rules: DEFAULT_RULES.clone(),
        sensitive_patterns: DEFAULT_SENSITIVE_PATTERNS.clone(),
        additional_skipped_directory_names: Default::default(),
        exposure_scan_limits: ExposureScanLimits::default(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn loads_expected_counts() {
        assert_eq!(DEFAULT_SENSITIVE_PATTERNS.len(), 49);
        assert_eq!(DEFAULT_RULES.len(), 18);
        assert!(DEFAULT_RULES.iter().any(|r| r.id == "cursor-ignore"));
        assert!(DEFAULT_SENSITIVE_PATTERNS.iter().any(|p| p.id == "env-files"));
    }

    #[test]
    fn cursor_ignore_is_required_and_scans() {
        let rule = DEFAULT_RULES.iter().find(|r| r.id == "cursor-ignore").unwrap();
        assert_eq!(rule.severity, RuleSeverity::Required);
        assert!(rule.scans_for_sensitive_patterns);
        assert_eq!(rule.tool, Some(ToolId::Cursor));
        let fix = rule.fix.as_ref().unwrap();
        assert_eq!(fix.relative_path, ".cursorignore");
        assert!(fix.contents.contains(".env*"));
    }

    #[test]
    fn filter_tools_keeps_agnostic_rules() {
        let tools = [ToolId::Cursor].into_iter().collect();
        let cfg = default_audit_configuration().filtered(Some(&tools));
        assert!(cfg.rules.iter().any(|r| r.id == "cursor-ignore"));
        assert!(cfg.rules.iter().any(|r| r.id == "git-ignore")); // tool-agnostic
        assert!(!cfg.rules.iter().any(|r| r.id == "claude-ignore"));
    }

    #[test]
    fn canonical_ignore_prefers_star_without_double_star() {
        let p = DEFAULT_SENSITIVE_PATTERNS
            .iter()
            .find(|p| p.id == "pem-files")
            .unwrap();
        assert_eq!(p.canonical_ignore_line(), "*.pem");
    }
}
