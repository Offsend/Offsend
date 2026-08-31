//! Project policy — port of WorkspacePolicyCore + `.offsend.yml` config bits.

mod allowlist;
mod audit;
mod audit_config;
mod audit_model;
mod check_report;
mod claude_deny;
mod config;
mod config_templates;
mod defaults;
mod drift;
mod exclude;
mod exposure;
mod fix_planner;
mod fixer;
mod glob;
mod ignore;
mod ignore_sync;
mod managed_block;
mod template;

pub use allowlist::{is_allowlisted, is_allowlisted_default, DEFAULT_ALLOWLIST_PATTERNS};
pub use audit::PrivacyAuditor;
pub use audit_config::{resolve_audit_configuration, AuditConfigOverrides};
pub use audit_model::*;
pub use claude_deny::{
    applies_to as claude_deny_applies_to, claude_path_glob, deny_rules_from_patterns,
    missing_managed_rules as claude_deny_missing, upsert as upsert_claude_deny, ClaudeDenyUpsert,
    SETTINGS_RELATIVE as CLAUDE_SETTINGS_RELATIVE,
};
pub use check_report::{
    build_check_report, check_report_to_json, render_check_report, CheckExposedPattern,
    CheckFixFile, CheckPatternMeta, CheckReport, CheckRuleMeta, CheckTotals,
    CHECK_REPORT_SCHEMA_VERSION,
};
pub use config::*;
pub use config_templates::*;
pub use defaults::{default_audit_configuration, DEFAULT_RULES, DEFAULT_SENSITIVE_PATTERNS};
pub use drift::{drift_missing_patterns, findings_for_files, ManagedIgnoreDriftFinding};
pub use exclude::PathExcludeMatcher;
pub use exposure::{
    exposed_among, exposed_finding, matching_pattern, scan_directory, BUILTIN_SKIPPED_DIRECTORY_NAMES,
};
pub use fix_planner::{
    FixItem, FixItemKind, FixScenario, FixSelection, PrivacyFixPlanner,
};
pub use fixer::{AppendOutcome, FixResult, PrivacyFixer};
pub use glob::GlobPattern;
pub use ignore::{IgnoreFileParser, IgnorePatternPathMatcher};
pub use ignore_sync::{
    IgnoreSyncReport, IgnoreSyncService, HOOKS_SECTION, IGNORE_FILES_SECTION,
};
pub use managed_block::{ManagedIgnoreBlock, UpsertResult};
pub use template::{
    claude_privacy_rule_contents, cursor_privacy_rule_contents, ignore_template_contents,
    managed_seed_contents, DEFAULT_IGNORE_PATTERNS, IGNORE_TEMPLATE_HEADER, PRIVACY_RULE_TEXT,
};
