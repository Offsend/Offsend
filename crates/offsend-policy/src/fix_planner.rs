//! Fix planning — port of Swift `AIWorkspacePrivacyFixPlanner`.

use crate::audit_model::{
    AuditConfiguration, AuditResult, FixStrategy, RuleSeverity,
};
use std::collections::HashSet;

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum FixItemKind {
    RuleFile {
        relative_path: String,
        strategy: FixStrategy,
    },
    SensitivePattern {
        canonical_line: String,
    },
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct FixItem {
    pub id: String,
    pub kind: FixItemKind,
    pub title: String,
    pub tool_name: Option<String>,
    pub severity: RuleSeverity,
}

#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct FixSelection {
    pub rule_ids: HashSet<String>,
    pub pattern_ids: HashSet<String>,
}

impl FixSelection {
    pub fn new(rule_ids: HashSet<String>, pattern_ids: HashSet<String>) -> Self {
        Self {
            rule_ids,
            pattern_ids,
        }
    }

    pub fn is_empty(&self) -> bool {
        self.rule_ids.is_empty() && self.pattern_ids.is_empty()
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum FixScenario {
    /// At least one scanning ignore file already exists.
    ExistingPolicyFiles,
    /// No scanning ignore files yet.
    NoPolicyFiles,
}

pub struct PrivacyFixPlanner;

impl PrivacyFixPlanner {
    pub fn fix_scenario(result: &AuditResult) -> FixScenario {
        let has_existing = result.rule_findings.iter().any(|f| {
            f.rule.scans_for_sensitive_patterns
                && f.is_satisfied()
                && !f.matched_relative_paths.is_empty()
        });
        if has_existing {
            FixScenario::ExistingPolicyFiles
        } else {
            FixScenario::NoPolicyFiles
        }
    }

    pub fn is_exposure_gap_rule_item(item: &FixItem, result: &AuditResult) -> bool {
        match &item.kind {
            FixItemKind::RuleFile {
                strategy: FixStrategy::MergeLines,
                ..
            } => Self::is_exposure_gap_policy_target(&item.id, result),
            _ => false,
        }
    }

    pub fn is_missing_rule_item(item: &FixItem, result: &AuditResult) -> bool {
        match &item.kind {
            FixItemKind::RuleFile { .. } => result
                .rule_findings
                .iter()
                .find(|f| f.rule.id == item.id)
                .is_some_and(|f| !f.is_satisfied()),
            FixItemKind::SensitivePattern { .. } => false,
        }
    }

    pub fn exposure_gap_rule_items<'a>(
        items: &'a [FixItem],
        result: &AuditResult,
    ) -> Vec<&'a FixItem> {
        items
            .iter()
            .filter(|item| Self::is_exposure_gap_rule_item(item, result))
            .collect()
    }

    pub fn missing_rule_items<'a>(items: &'a [FixItem], result: &AuditResult) -> Vec<&'a FixItem> {
        items
            .iter()
            .filter(|item| Self::is_missing_rule_item(item, result))
            .collect()
    }

    /// Missing policy ignore files for other AI tools (`.claudeignore`, `.aiexclude`, …).
    pub fn missing_ignore_file_items(
        result: &AuditResult,
        configuration: &AuditConfiguration,
    ) -> Vec<FixItem> {
        let mut items = Vec::new();

        for finding in &result.rule_findings {
            let rule = &finding.rule;
            if finding.is_satisfied() {
                continue;
            }
            if !rule.scans_for_sensitive_patterns {
                continue;
            }
            if rule.severity == RuleSeverity::Informational {
                continue;
            }
            let Some(fix) = configuration
                .rules
                .iter()
                .find(|r| r.id == rule.id)
                .and_then(|r| r.fix.as_ref())
                .or(rule.fix.as_ref())
            else {
                continue;
            };
            items.push(FixItem {
                id: rule.id.clone(),
                kind: FixItemKind::RuleFile {
                    relative_path: fix.relative_path.clone(),
                    strategy: fix.strategy,
                },
                title: rule.title.clone(),
                tool_name: Some(rule.tool_name.clone()),
                severity: rule.severity,
            });
        }

        items.sort_by(sort_fix_items);
        items
    }

    pub fn fix_items(result: &AuditResult, configuration: &AuditConfiguration) -> Vec<FixItem> {
        let mut items = Vec::new();
        let mut added_rule_ids = HashSet::new();

        for finding in &result.rule_findings {
            if finding.is_satisfied() || finding.rule.severity == RuleSeverity::Informational {
                continue;
            }
            let rule = &finding.rule;
            let Some(fix) = configuration
                .rules
                .iter()
                .find(|r| r.id == rule.id)
                .and_then(|r| r.fix.as_ref())
                .or(rule.fix.as_ref())
            else {
                continue;
            };
            items.push(FixItem {
                id: rule.id.clone(),
                kind: FixItemKind::RuleFile {
                    relative_path: fix.relative_path.clone(),
                    strategy: fix.strategy,
                },
                title: rule.title.clone(),
                tool_name: Some(rule.tool_name.clone()),
                severity: rule.severity,
            });
            added_rule_ids.insert(rule.id.clone());
        }

        for finding in &result.rule_findings {
            if !(finding.is_satisfied()
                && finding.rule.scans_for_sensitive_patterns
                && !finding.matched_relative_paths.is_empty()
                && !finding.exposed_relative_paths.is_empty()
                && finding.rule.severity != RuleSeverity::Informational)
            {
                continue;
            }
            if added_rule_ids.contains(&finding.rule.id) {
                continue;
            }
            let Some(fix) = configuration
                .rules
                .iter()
                .find(|r| r.id == finding.rule.id)
                .and_then(|r| r.fix.as_ref())
                .or(finding.rule.fix.as_ref())
            else {
                continue;
            };
            items.push(FixItem {
                id: finding.rule.id.clone(),
                kind: FixItemKind::RuleFile {
                    relative_path: fix.relative_path.clone(),
                    strategy: FixStrategy::MergeLines,
                },
                title: finding.rule.title.clone(),
                tool_name: Some(finding.rule.tool_name.clone()),
                severity: RuleSeverity::Recommended,
            });
            added_rule_ids.insert(finding.rule.id.clone());
        }

        for finding in result.missing_sensitive_patterns() {
            items.push(FixItem {
                id: finding.pattern.id.clone(),
                kind: FixItemKind::SensitivePattern {
                    canonical_line: finding.pattern.canonical_ignore_line().to_string(),
                },
                title: finding.pattern.title.clone(),
                tool_name: None,
                severity: finding.pattern.severity,
            });
        }

        items.sort_by(sort_fix_items);
        items
    }

    pub fn default_selection(items: &[FixItem], result: &AuditResult) -> FixSelection {
        let mut selection = FixSelection::default();
        let pattern_items: Vec<&FixItem> = items
            .iter()
            .filter(|item| matches!(item.kind, FixItemKind::SensitivePattern { .. }))
            .collect();

        for item in &pattern_items {
            selection.pattern_ids.insert(item.id.clone());
        }

        if pattern_items.is_empty() {
            for item in items {
                if matches!(item.kind, FixItemKind::RuleFile { .. }) {
                    selection.rule_ids.insert(item.id.clone());
                }
            }
            return selection;
        }

        for item in items {
            if !matches!(item.kind, FixItemKind::RuleFile { .. }) {
                continue;
            }
            if item.severity == RuleSeverity::Required
                || Self::is_exposure_gap_policy_target(&item.id, result)
            {
                selection.rule_ids.insert(item.id.clone());
            }
        }

        if selection.rule_ids.is_empty() {
            for item in items {
                if matches!(item.kind, FixItemKind::RuleFile { .. }) {
                    selection.rule_ids.insert(item.id.clone());
                }
            }
        }

        selection
    }

    pub fn selection_from_ids(selected_item_ids: &HashSet<String>, items: &[FixItem]) -> FixSelection {
        let mut selection = FixSelection::default();
        for item in items {
            if !selected_item_ids.contains(&item.id) {
                continue;
            }
            match item.kind {
                FixItemKind::RuleFile { .. } => {
                    selection.rule_ids.insert(item.id.clone());
                }
                FixItemKind::SensitivePattern { .. } => {
                    selection.pattern_ids.insert(item.id.clone());
                }
            }
        }
        selection
    }

    pub fn planned_relative_paths(
        result: &AuditResult,
        configuration: &AuditConfiguration,
        selection: &FixSelection,
        created_relative_paths: &HashSet<String>,
    ) -> Vec<String> {
        let mut paths = HashSet::new();

        for finding in &result.rule_findings {
            if finding.is_satisfied() || finding.rule.severity == RuleSeverity::Informational {
                continue;
            }
            if !selection.rule_ids.contains(&finding.rule.id) {
                continue;
            }
            if let Some(fix) = configuration
                .rules
                .iter()
                .find(|r| r.id == finding.rule.id)
                .and_then(|r| r.fix.as_ref())
                .or(finding.rule.fix.as_ref())
            {
                paths.insert(fix.relative_path.clone());
            }
        }

        if !selection.pattern_ids.is_empty() {
            paths.extend(Self::pattern_target_relative_paths(
                result,
                configuration,
                Some(selection),
                created_relative_paths,
            ));
        }

        let mut sorted: Vec<String> = paths.into_iter().collect();
        sorted.sort();
        sorted
    }

    /// Ignore files that should receive selected sensitive patterns.
    pub fn pattern_target_relative_paths(
        result: &AuditResult,
        configuration: &AuditConfiguration,
        selection: Option<&FixSelection>,
        created_relative_paths: &HashSet<String>,
    ) -> Vec<String> {
        let mut paths = HashSet::new();

        if let Some(selection) = selection {
            let selected_scan_rules: Vec<_> = configuration
                .rules
                .iter()
                .filter(|r| r.scans_for_sensitive_patterns && selection.rule_ids.contains(&r.id))
                .collect();
            for rule in &selected_scan_rules {
                if let Some(fix) = &rule.fix {
                    paths.insert(fix.relative_path.clone());
                }
            }
            for finding in &result.rule_findings {
                if finding.rule.scans_for_sensitive_patterns
                    && selection.rule_ids.contains(&finding.rule.id)
                {
                    paths.extend(finding.matched_relative_paths.iter().cloned());
                }
            }
            for path in created_relative_paths {
                if selected_scan_rules
                    .iter()
                    .any(|r| r.fix.as_ref().is_some_and(|f| &f.relative_path == path))
                {
                    paths.insert(path.clone());
                }
            }
            let mut sorted: Vec<String> = paths.into_iter().collect();
            sorted.sort();
            return sorted;
        }

        for finding in &result.rule_findings {
            if !finding.rule.scans_for_sensitive_patterns {
                continue;
            }
            paths.extend(finding.matched_relative_paths.iter().cloned());
            if let Some(fix) = &finding.rule.fix {
                paths.insert(fix.relative_path.clone());
            }
        }
        for rule in &configuration.rules {
            if rule.scans_for_sensitive_patterns {
                if let Some(fix) = &rule.fix {
                    paths.insert(fix.relative_path.clone());
                }
            }
        }
        for path in created_relative_paths {
            if configuration.rules.iter().any(|rule| {
                rule.scans_for_sensitive_patterns
                    && rule
                        .fix
                        .as_ref()
                        .is_some_and(|f| &f.relative_path == path)
            }) {
                paths.insert(path.clone());
            }
        }

        let mut sorted: Vec<String> = paths.into_iter().collect();
        sorted.sort();
        sorted
    }

    fn is_exposure_gap_policy_target(item_id: &str, result: &AuditResult) -> bool {
        result
            .rule_findings
            .iter()
            .find(|f| f.rule.id == item_id)
            .is_some_and(|finding| {
                finding.is_satisfied()
                    && finding.rule.scans_for_sensitive_patterns
                    && !finding.exposed_relative_paths.is_empty()
            })
    }
}

fn sort_fix_items(lhs: &FixItem, rhs: &FixItem) -> std::cmp::Ordering {
    let lhs_rank = severity_rank(lhs.severity);
    let rhs_rank = severity_rank(rhs.severity);
    if lhs_rank != rhs_rank {
        return lhs_rank.cmp(&rhs_rank);
    }

    match (&lhs.kind, &rhs.kind) {
        (FixItemKind::SensitivePattern { .. }, FixItemKind::RuleFile { .. }) => {
            std::cmp::Ordering::Less
        }
        (FixItemKind::RuleFile { .. }, FixItemKind::SensitivePattern { .. }) => {
            std::cmp::Ordering::Greater
        }
        _ => lhs.title.to_lowercase().cmp(&rhs.title.to_lowercase()),
    }
}

fn severity_rank(severity: RuleSeverity) -> u8 {
    match severity {
        RuleSeverity::Required => 0,
        RuleSeverity::Recommended => 1,
        RuleSeverity::Informational => 2,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::audit::PrivacyAuditor;
    use crate::defaults::default_audit_configuration;
    use std::fs;

    fn temp_dir(name: &str) -> std::path::PathBuf {
        let dir = std::env::temp_dir().join(format!(
            "offsend-policy-planner-{}-{}",
            name,
            std::process::id()
        ));
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(&dir).unwrap();
        dir
    }

    #[test]
    fn fix_items_includes_missing_rules() {
        let dir = temp_dir("missing-rules");
        let result = PrivacyAuditor::audit(&dir);
        let items = PrivacyFixPlanner::fix_items(&result, &default_audit_configuration());
        let _ = fs::remove_dir_all(&dir);

        assert!(PrivacyFixPlanner::missing_rule_items(&items, &result)
            .iter()
            .any(|item| item.id == "cursor-ignore"));
        assert!(items.iter().any(|item| {
            item.id == "cursor-ignore"
                && matches!(item.kind, FixItemKind::RuleFile { .. })
                && !PrivacyFixPlanner::is_exposure_gap_rule_item(item, &result)
        }));
    }
}
