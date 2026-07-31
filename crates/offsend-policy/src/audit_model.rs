//! Audit domain models — port of Swift `AIWorkspacePrivacyAuditModels`.

use crate::config::ToolId;
use std::collections::HashSet;
use std::path::PathBuf;
use std::time::Duration;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RuleSeverity {
    Required,
    Recommended,
    Informational,
}

impl RuleSeverity {
    pub fn parse(s: &str) -> Self {
        match s {
            "required" => Self::Required,
            "informational" => Self::Informational,
            _ => Self::Recommended,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SensitiveCategory {
    Secret,
    Cloud,
    Signing,
    Pii,
    History,
    Other,
}

impl SensitiveCategory {
    pub fn parse(s: &str) -> Self {
        match s {
            "secret" => Self::Secret,
            "cloud" => Self::Cloud,
            "signing" => Self::Signing,
            "pii" => Self::Pii,
            "history" => Self::History,
            _ => Self::Other,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum FixStrategy {
    CreateIfMissing,
    MergeLines,
    KeepManagedContent,
}

impl FixStrategy {
    pub fn parse(s: Option<&str>) -> Self {
        match s {
            Some("keepManagedContent") => Self::KeepManagedContent,
            Some("createIfMissing") => Self::CreateIfMissing,
            _ => Self::MergeLines,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct FileFix {
    pub relative_path: String,
    pub contents: String,
    pub strategy: FixStrategy,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PrivacyRule {
    pub id: String,
    pub tool_name: String,
    pub tool: Option<ToolId>,
    pub title: String,
    pub relative_path_patterns: Vec<String>,
    pub severity: RuleSeverity,
    pub scans_for_sensitive_patterns: bool,
    pub remediation: String,
    pub fix: Option<FileFix>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SensitivePattern {
    pub id: String,
    pub title: String,
    pub accepted_patterns: Vec<String>,
    pub severity: RuleSeverity,
    pub category: SensitiveCategory,
    pub remediation: String,
}

impl SensitivePattern {
    pub fn canonical_ignore_line(&self) -> &str {
        self.accepted_patterns
            .iter()
            .find(|p| !p.contains("**") && p.contains('*'))
            .or_else(|| self.accepted_patterns.iter().find(|p| !p.contains("**")))
            .map(|s| s.as_str())
            .unwrap_or(&self.accepted_patterns[0])
    }
}

#[derive(Debug, Clone)]
pub struct AuditConfiguration {
    pub rules: Vec<PrivacyRule>,
    pub sensitive_patterns: Vec<SensitivePattern>,
    pub additional_skipped_directory_names: HashSet<String>,
    pub exposure_scan_limits: ExposureScanLimits,
}

impl AuditConfiguration {
    pub fn filtered(mut self, tools: Option<&HashSet<ToolId>>) -> Self {
        let Some(tools) = tools else {
            return self;
        };
        self.rules.retain(|rule| match rule.tool {
            None => true,
            Some(t) => tools.contains(&t),
        });
        self
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct ExposureScanLimits {
    pub max_files: Option<usize>,
    pub time_limit: Option<Duration>,
}

impl Default for ExposureScanLimits {
    fn default() -> Self {
        Self {
            max_files: Some(100_000),
            time_limit: Some(Duration::from_secs(30)),
        }
    }
}

impl ExposureScanLimits {
    pub const UNLIMITED: Self = Self {
        max_files: None,
        time_limit: None,
    };
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum AuditStatus {
    Pass,
    Warning,
    Fail,
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub enum ExposureScanCompletion {
    Complete,
    Truncated { max_files: usize, files_scanned: usize },
    TimedOut { time_limit_secs: f64, files_scanned: usize },
}

impl ExposureScanCompletion {
    pub fn is_complete(self) -> bool {
        matches!(self, Self::Complete)
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RuleFinding {
    pub rule: PrivacyRule,
    pub matched_relative_paths: Vec<String>,
    pub exposed_relative_paths: Vec<String>,
}

impl RuleFinding {
    pub fn is_satisfied(&self) -> bool {
        !self.matched_relative_paths.is_empty()
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SensitivePatternFinding {
    pub pattern: SensitivePattern,
    pub matched_ignore_file_paths: Vec<String>,
    pub exposed_relative_paths: Vec<String>,
}

impl SensitivePatternFinding {
    pub fn is_satisfied(&self) -> bool {
        self.exposed_relative_paths.is_empty()
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct AuditError {
    pub id: String,
    pub message: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ExposedFileFinding {
    pub relative_path: String,
    pub pattern: SensitivePattern,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ExposureIndex {
    pub sensitive_relative_paths: HashSet<String>,
}

#[derive(Debug, Clone)]
pub struct ExposureScanResult {
    pub exposed_files: Vec<ExposedFileFinding>,
    pub indexed_sensitive_paths: HashSet<String>,
    pub files_scanned: usize,
    pub completion: ExposureScanCompletion,
}

#[derive(Debug, Clone)]
pub struct AuditResult {
    pub directory: PathBuf,
    pub status: AuditStatus,
    pub rule_findings: Vec<RuleFinding>,
    pub sensitive_pattern_findings: Vec<SensitivePatternFinding>,
    pub errors: Vec<AuditError>,
    pub exposure_index: Option<ExposureIndex>,
    pub exposure_scan_completion: ExposureScanCompletion,
}

impl AuditResult {
    pub fn missing_sensitive_patterns(&self) -> Vec<&SensitivePatternFinding> {
        self.sensitive_pattern_findings
            .iter()
            .filter(|f| !f.is_satisfied())
            .collect()
    }

    pub fn missing_required_rules(&self) -> Vec<&RuleFinding> {
        self.rule_findings
            .iter()
            .filter(|f| !f.is_satisfied() && f.rule.severity == RuleSeverity::Required)
            .collect()
    }
}
