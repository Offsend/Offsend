//! Anonymized Check / Scan API report — matches Swift `ReportReporter` schema v1.

use crate::audit::PrivacyAuditor;
use crate::audit_model::{
    AuditConfiguration, AuditResult, FileFix, FixStrategy, RuleSeverity, SensitiveCategory,
};
use crate::config::OffsendProjectConfig;
use serde::Serialize;
use std::collections::{BTreeMap, HashSet};
use std::path::Path;
use std::time::{SystemTime, UNIX_EPOCH};

/// Bump when the JSON shape changes incompatibly (parity with Swift `ReportReporter`).
pub const CHECK_REPORT_SCHEMA_VERSION: u32 = 1;

#[derive(Debug, Clone, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct CheckFixFile {
    pub path: String,
    pub contents: String,
}

#[derive(Debug, Clone, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct CheckRuleMeta {
    pub id: String,
    pub title: String,
    pub tool_name: String,
    pub severity: String,
    pub scans_for_sensitive_patterns: bool,
    pub remediation: String,
}

#[derive(Debug, Clone, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct CheckPatternMeta {
    pub id: String,
    pub title: String,
    pub remediation: String,
}

#[derive(Debug, Clone, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct CheckReport {
    pub schema_version: u32,
    pub ruleset_version: String,
    pub tool_version: String,
    pub generated_at: String,
    pub scan_complete: bool,
    pub ignore_files_present: BTreeMap<String, bool>,
    pub exposed_patterns: Vec<CheckExposedPattern>,
    pub totals: CheckTotals,
    pub errors: Vec<String>,
    /// Catalog of rules used for this scan (HTML / fix labels).
    pub rules: Vec<CheckRuleMeta>,
    /// Catalog of sensitive patterns used for this scan.
    pub patterns: Vec<CheckPatternMeta>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub fix_files: Vec<CheckFixFile>,
}

#[derive(Debug, Clone, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct CheckExposedPattern {
    pub id: String,
    pub severity: String,
    pub category: String,
    pub count: usize,
}

#[derive(Debug, Clone, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct CheckTotals {
    pub exposed_files: usize,
    pub exposed_pattern_types: usize,
}

/// Run a privacy audit and build a Check-compatible anonymized report (+ fix file contents).
pub fn build_check_report(directory: &Path, tool_version: &str) -> CheckReport {
    let (configuration, managed_files_expected_missing) = configuration_for(directory);
    let audit = PrivacyAuditor::audit_with(directory, &configuration);
    render_check_report(
        &audit,
        &configuration,
        tool_version,
        managed_files_expected_missing,
        &iso8601_now(),
    )
}

/// Render Check JSON from an already-computed audit (for tests / reuse).
pub fn render_check_report(
    audit: &AuditResult,
    configuration: &AuditConfiguration,
    tool_version: &str,
    managed_files_expected_missing: bool,
    generated_at: &str,
) -> CheckReport {
    let ruleset_version = ruleset_version(configuration);
    let directory_unavailable = audit.errors.iter().any(|e| e.id == "directory-unavailable");

    let finding_by_rule_id: BTreeMap<&str, &crate::audit_model::RuleFinding> = audit
        .rule_findings
        .iter()
        .map(|f| (f.rule.id.as_str(), f))
        .collect();

    let mut ignore_files_present = BTreeMap::new();
    for rule in &configuration.rules {
        let satisfied = finding_by_rule_id
            .get(rule.id.as_str())
            .map(|f| f.is_satisfied())
            .unwrap_or(false);
        let present = satisfied
            || (managed_files_expected_missing && is_materialized_by_ignore_sync(rule));
        ignore_files_present.insert(rule.id.clone(), present);
    }

    let mut exposed_patterns: Vec<CheckExposedPattern> = if directory_unavailable {
        vec![]
    } else {
        audit
            .sensitive_pattern_findings
            .iter()
            .filter(|f| !f.exposed_relative_paths.is_empty())
            .map(|f| CheckExposedPattern {
                id: f.pattern.id.clone(),
                severity: severity_str(f.pattern.severity).into(),
                category: category_str(f.pattern.category).into(),
                count: f.exposed_relative_paths.len(),
            })
            .collect()
    };
    exposed_patterns.sort_by(|a, b| {
        severity_rank(&a.severity)
            .cmp(&severity_rank(&b.severity))
            .then_with(|| a.id.cmp(&b.id))
    });

    let mut exposed_paths: HashSet<&str> = HashSet::new();
    if !directory_unavailable {
        for f in &audit.sensitive_pattern_findings {
            for path in &f.exposed_relative_paths {
                exposed_paths.insert(path.as_str());
            }
        }
    }

    let fix_files = if directory_unavailable {
        vec![]
    } else {
        check_fix_files(audit, configuration, &ignore_files_present, !exposed_patterns.is_empty())
    };

    let rules: Vec<CheckRuleMeta> = configuration
        .rules
        .iter()
        .map(|r| CheckRuleMeta {
            id: r.id.clone(),
            title: r.title.clone(),
            tool_name: r.tool_name.clone(),
            severity: severity_str(r.severity).into(),
            scans_for_sensitive_patterns: r.scans_for_sensitive_patterns,
            remediation: r.remediation.clone(),
        })
        .collect();
    let patterns: Vec<CheckPatternMeta> = configuration
        .sensitive_patterns
        .iter()
        .map(|p| CheckPatternMeta {
            id: p.id.clone(),
            title: p.title.clone(),
            remediation: p.remediation.clone(),
        })
        .collect();

    CheckReport {
        schema_version: CHECK_REPORT_SCHEMA_VERSION,
        ruleset_version,
        tool_version: tool_version.to_string(),
        generated_at: generated_at.to_string(),
        scan_complete: !directory_unavailable && audit.exposure_scan_completion.is_complete(),
        ignore_files_present,
        totals: CheckTotals {
            exposed_files: exposed_paths.len(),
            exposed_pattern_types: exposed_patterns.len(),
        },
        exposed_patterns,
        errors: audit.errors.iter().map(|e| e.id.clone()).collect(),
        rules,
        patterns,
        fix_files,
    }
}

pub fn check_report_to_json(report: &CheckReport) -> Result<String, String> {
    serde_json::to_string_pretty(report).map_err(|e| format!("JSON serialize failed: {e}"))
}

fn configuration_for(directory: &Path) -> (AuditConfiguration, bool) {
    let mut managed_files_expected_missing = false;
    if let Ok(Some((_, cfg))) = OffsendProjectConfig::find_and_load(directory) {
        if let Some(ignore) = cfg.ignore.as_ref() {
            managed_files_expected_missing = !ignore.commits_ignore_files();
        }
    }
    let configuration = crate::resolve_audit_configuration(
        directory,
        &crate::AuditConfigOverrides::new(),
    );
    (configuration, managed_files_expected_missing)
}

fn is_materialized_by_ignore_sync(rule: &crate::audit_model::PrivacyRule) -> bool {
    let Some(fix) = &rule.fix else {
        return false;
    };
    rule.scans_for_sensitive_patterns || fix.strategy == FixStrategy::KeepManagedContent
}

fn check_fix_files(
    _audit: &AuditResult,
    configuration: &AuditConfiguration,
    ignore_files_present: &BTreeMap<String, bool>,
    has_exposed_patterns: bool,
) -> Vec<CheckFixFile> {
    let rules_by_id: BTreeMap<&str, &crate::audit_model::PrivacyRule> = configuration
        .rules
        .iter()
        .map(|r| (r.id.as_str(), r))
        .collect();

    let mut missing: Vec<&FileFix> = Vec::new();
    let mut refreshed: Vec<&FileFix> = Vec::new();

    for (rule_id, present) in ignore_files_present {
        let Some(rule) = rules_by_id.get(rule_id.as_str()) else {
            continue;
        };
        if !rule.scans_for_sensitive_patterns || rule.severity == RuleSeverity::Informational {
            continue;
        }
        let Some(fix) = rule.fix.as_ref() else {
            continue;
        };
        if !*present {
            missing.push(fix);
        } else if has_exposed_patterns {
            refreshed.push(fix);
        }
    }

    let mut files = Vec::new();
    let mut written_paths = HashSet::new();
    for fix in missing.into_iter().chain(refreshed.into_iter()) {
        if written_paths.insert(fix.relative_path.clone()) {
            files.push(CheckFixFile {
                path: fix.relative_path.clone(),
                contents: fix.contents.clone(),
            });
        }
    }
    files.sort_by(|a, b| a.path.cmp(&b.path));
    files
}

fn ruleset_version(configuration: &AuditConfiguration) -> String {
    let mut components: Vec<String> = Vec::new();
    let mut rules = configuration.rules.clone();
    rules.sort_by(|a, b| a.id.cmp(&b.id));
    for rule in &rules {
        components.push(format!(
            "r:{}:{}",
            rule.id,
            severity_str(rule.severity)
        ));
    }
    let mut patterns = configuration.sensitive_patterns.clone();
    patterns.sort_by(|a, b| a.id.cmp(&b.id));
    for pattern in &patterns {
        let accepted = pattern.accepted_patterns.join(",");
        components.push(format!(
            "p:{}:{}:{}",
            pattern.id,
            severity_str(pattern.severity),
            accepted
        ));
    }
    djb2_hex(&components.join("|"))
}

fn djb2_hex(string: &str) -> String {
    let mut hash: u64 = 5381;
    for byte in string.as_bytes() {
        hash = hash.wrapping_mul(33).wrapping_add(u64::from(*byte));
    }
    format!("{hash:x}")
}

fn severity_str(severity: RuleSeverity) -> &'static str {
    match severity {
        RuleSeverity::Required => "required",
        RuleSeverity::Recommended => "recommended",
        RuleSeverity::Informational => "informational",
    }
}

fn category_str(category: SensitiveCategory) -> &'static str {
    match category {
        SensitiveCategory::Secret => "secret",
        SensitiveCategory::Cloud => "cloud",
        SensitiveCategory::Signing => "signing",
        SensitiveCategory::Pii => "pii",
        SensitiveCategory::History => "history",
        SensitiveCategory::Other => "other",
    }
}

fn severity_rank(severity: &str) -> u8 {
    match severity {
        "required" => 0,
        "recommended" => 1,
        _ => 2,
    }
}

fn iso8601_now() -> String {
    let secs = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0);
    // Compact UTC timestamp without pulling chrono (YYYY-MM-DDTHH:MM:SSZ via manual math).
    let days = secs / 86_400;
    let time_of_day = secs % 86_400;
    let hour = time_of_day / 3600;
    let min = (time_of_day % 3600) / 60;
    let sec = time_of_day % 60;
    let (year, month, day) = civil_from_days(days as i64);
    format!("{year:04}-{month:02}-{day:02}T{hour:02}:{min:02}:{sec:02}Z")
}

/// Days since Unix epoch → (year, month, day). Algorithm from Howard Hinnant.
fn civil_from_days(days: i64) -> (i32, u32, u32) {
    let z = days + 719_468;
    let era = if z >= 0 { z } else { z - 146_096 } / 146_097;
    let doe = (z - era * 146_097) as u64;
    let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146_096) / 365;
    let y = yoe as i64 + era * 400;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = doy - (153 * mp + 2) / 5 + 1;
    let m = if mp < 10 { mp + 3 } else { mp - 9 };
    let y = if m <= 2 { y + 1 } else { y };
    (y as i32, m as u32, d as u32)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;

    #[test]
    fn check_report_detects_env_exposure() {
        let dir = std::env::temp_dir().join(format!(
            "offsend-check-report-{}",
            std::time::SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        fs::create_dir_all(&dir).unwrap();
        fs::write(dir.join(".env"), "SECRET=abc\n").unwrap();
        fs::write(dir.join("README.md"), "# hi\n").unwrap();

        let report = build_check_report(&dir, "test-1.0.0");
        assert!(report.scan_complete);
        assert_eq!(report.schema_version, 1);
        assert_eq!(report.tool_version, "test-1.0.0");
        assert!(!report.exposed_patterns.is_empty());
        assert!(report.totals.exposed_files > 0);
        assert!(!report.fix_files.is_empty());
        assert!(report.fix_files.iter().any(|f| f.path == ".cursorignore"));

        let json = check_report_to_json(&report).unwrap();
        assert!(json.contains("\"schemaVersion\""));
        assert!(json.contains("\"exposedPatterns\""));
        assert!(json.contains("\"fixFiles\""));

        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn managed_ignore_commit_false_marks_scanning_rules_present() {
        let dir = std::env::temp_dir().join(format!(
            "offsend-check-managed-{}",
            std::time::SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        fs::create_dir_all(&dir).unwrap();
        fs::write(
            dir.join(".offsend.yml"),
            "version: 1\nignore:\n  commit: false\n  patterns:\n    - \".env*\"\n",
        )
        .unwrap();
        fs::write(dir.join(".env"), "x=1\n").unwrap();

        let report = build_check_report(&dir, "test");
        assert_eq!(report.ignore_files_present.get("cursor-ignore"), Some(&true));
        assert_eq!(report.ignore_files_present.get("claude-ignore"), Some(&true));
        assert_eq!(report.ignore_files_present.get("agents-md"), Some(&false));

        let _ = fs::remove_dir_all(&dir);
    }
}
