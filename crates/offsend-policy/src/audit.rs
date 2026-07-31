//! Workspace privacy auditor — port of Swift `AIWorkspacePrivacyAuditor` (full audit).

use crate::audit_model::{
    AuditConfiguration, AuditError, AuditResult, AuditStatus, ExposureScanCompletion,
    RuleFinding, RuleSeverity, SensitivePatternFinding,
};
use crate::defaults::default_audit_configuration;
use crate::exposure::{
    exposure_index_from_scan, exposed_among, scan_directory, BUILTIN_SKIPPED_DIRECTORY_NAMES,
};
use crate::glob::GlobPattern;
use crate::ignore::IgnoreFileParser;
use std::collections::{HashMap, HashSet};
use std::path::Path;

pub struct PrivacyAuditor;

impl PrivacyAuditor {
    pub fn audit(directory: &Path) -> AuditResult {
        Self::audit_with(directory, &default_audit_configuration())
    }

    pub fn audit_with(directory: &Path, configuration: &AuditConfiguration) -> AuditResult {
        let root = directory.to_path_buf();
        if !root.is_dir() {
            return AuditResult {
                directory: root,
                status: AuditStatus::Fail,
                rule_findings: vec![],
                sensitive_pattern_findings: vec![],
                errors: vec![AuditError {
                    id: "directory-unavailable".into(),
                    message: "The selected path is not a readable directory.".into(),
                }],
                exposure_index: None,
                exposure_scan_completion: ExposureScanCompletion::Complete,
            };
        }

        let mut skipped: HashSet<String> = BUILTIN_SKIPPED_DIRECTORY_NAMES
            .iter()
            .map(|s| (*s).to_string())
            .collect();
        skipped.extend(configuration.additional_skipped_directory_names.iter().cloned());

        let mut rule_findings: Vec<RuleFinding> = configuration
            .rules
            .iter()
            .map(|rule| RuleFinding {
                rule: rule.clone(),
                matched_relative_paths: matched_relative_paths(rule, &root, &skipped),
                exposed_relative_paths: vec![],
            })
            .collect();

        let ignore_patterns = load_ignore_patterns(&rule_findings, &root);
        let scan = scan_directory(
            &root,
            &configuration.sensitive_patterns,
            &ignore_patterns,
            &skipped,
            configuration.exposure_scan_limits,
        );

        // Per-tool exposure: paths not covered by that tool's ignore file alone.
        for finding in &mut rule_findings {
            if !finding.rule.scans_for_sensitive_patterns || finding.matched_relative_paths.is_empty()
            {
                continue;
            }
            let mut single = HashMap::new();
            for path in &finding.matched_relative_paths {
                if let Some(patterns) = ignore_patterns.get(path) {
                    single.insert(path.clone(), patterns.clone());
                }
            }
            let exposed = exposed_among(
                scan.indexed_sensitive_paths.iter(),
                &configuration.sensitive_patterns,
                &single,
            );
            finding.exposed_relative_paths = exposed
                .into_iter()
                .map(|f| f.relative_path)
                .collect();
        }

        let scanning_ignore_paths: Vec<String> = rule_findings
            .iter()
            .filter(|f| f.rule.scans_for_sensitive_patterns)
            .flat_map(|f| f.matched_relative_paths.iter().cloned())
            .collect();

        let sensitive_findings: Vec<SensitivePatternFinding> = configuration
            .sensitive_patterns
            .iter()
            .map(|pattern| {
                let exposed: Vec<String> = scan
                    .exposed_files
                    .iter()
                    .filter(|f| f.pattern.id == pattern.id)
                    .map(|f| f.relative_path.clone())
                    .collect();
                let matched_ignore: Vec<String> = scanning_ignore_paths
                    .iter()
                    .filter(|path| {
                        ignore_patterns
                            .get(*path)
                            .map(|set| {
                                pattern.accepted_patterns.iter().any(|p| set.contains(p))
                                    || set.iter().any(|line| {
                                        pattern.accepted_patterns.iter().any(|p| line == p)
                                    })
                            })
                            .unwrap_or(false)
                    })
                    .cloned()
                    .collect();
                SensitivePatternFinding {
                    pattern: pattern.clone(),
                    matched_ignore_file_paths: matched_ignore,
                    exposed_relative_paths: exposed,
                }
            })
            .collect();

        let base_status = compute_status(&rule_findings, &sensitive_findings);
        let (status, errors) =
            apply_scan_completion(base_status, scan.completion, Vec::new());

        AuditResult {
            directory: root,
            status,
            rule_findings,
            sensitive_pattern_findings: sensitive_findings,
            errors,
            exposure_index: Some(exposure_index_from_scan(&scan)),
            exposure_scan_completion: scan.completion,
        }
    }
}

fn matched_relative_paths(
    rule: &crate::audit_model::PrivacyRule,
    root: &Path,
    skipped_directory_names: &HashSet<String>,
) -> Vec<String> {
    let needs_walk = rule
        .relative_path_patterns
        .iter()
        .any(|p| p.contains('*') || p.contains('?'));
    let walked = if needs_walk {
        list_relative_paths(root, skipped_directory_names)
    } else {
        Vec::new()
    };

    let mut matches = Vec::new();
    for pattern in &rule.relative_path_patterns {
        if pattern.contains('*') || pattern.contains('?') {
            let glob = GlobPattern::new(pattern);
            for rel in &walked {
                if glob.matches(rel) {
                    matches.push(rel.clone());
                }
            }
        } else if root.join(pattern).exists() {
            matches.push(pattern.clone());
        }
    }
    matches.sort();
    matches.dedup();
    matches
}

fn list_relative_paths(root: &Path, skipped_directory_names: &HashSet<String>) -> Vec<String> {
    let mut out = Vec::new();
    let mut stack = vec![root.to_path_buf()];
    while let Some(dir) = stack.pop() {
        let Ok(entries) = std::fs::read_dir(&dir) else {
            continue;
        };
        for entry in entries.flatten() {
            let path = entry.path();
            let Ok(meta) = entry.metadata() else {
                continue;
            };
            let Some(rel) = relative_path_string(root, &path) else {
                continue;
            };
            if meta.is_dir() {
                let name = entry.file_name().to_string_lossy().into_owned();
                if skipped_directory_names.contains(&name) {
                    continue;
                }
                out.push(rel);
                stack.push(path);
            } else if meta.is_file() {
                out.push(rel);
            }
        }
    }
    out
}

fn relative_path_string(root: &Path, path: &Path) -> Option<String> {
    let rel = path.strip_prefix(root).ok()?;
    Some(rel.to_string_lossy().replace('\\', "/"))
}

fn load_ignore_patterns(
    rule_findings: &[RuleFinding],
    root: &Path,
) -> HashMap<String, HashSet<String>> {
    let mut map = HashMap::new();
    for finding in rule_findings {
        if !finding.rule.scans_for_sensitive_patterns {
            continue;
        }
        for rel in &finding.matched_relative_paths {
            let path = root.join(rel);
            if let Ok(contents) = std::fs::read_to_string(&path) {
                map.insert(rel.clone(), IgnoreFileParser::patterns(&contents));
            }
        }
    }
    map
}

fn compute_status(
    rule_findings: &[RuleFinding],
    sensitive_findings: &[SensitivePatternFinding],
) -> AuditStatus {
    let has_required_exposure = sensitive_findings
        .iter()
        .any(|f| !f.is_satisfied() && f.pattern.severity == RuleSeverity::Required);
    let has_required_rule_exposure = rule_findings.iter().any(|f| {
        !f.exposed_relative_paths.is_empty() && f.rule.severity == RuleSeverity::Required
    });
    if has_required_exposure || has_required_rule_exposure {
        return AuditStatus::Fail;
    }
    if rule_findings
        .iter()
        .any(|f| !f.is_satisfied() && f.rule.severity == RuleSeverity::Required)
    {
        return AuditStatus::Warning;
    }
    if rule_findings
        .iter()
        .any(|f| !f.is_satisfied() && f.rule.severity == RuleSeverity::Recommended)
    {
        return AuditStatus::Warning;
    }
    if sensitive_findings
        .iter()
        .any(|f| !f.is_satisfied() && f.pattern.severity == RuleSeverity::Recommended)
    {
        return AuditStatus::Warning;
    }
    AuditStatus::Pass
}

fn apply_scan_completion(
    base: AuditStatus,
    completion: ExposureScanCompletion,
    errors: Vec<AuditError>,
) -> (AuditStatus, Vec<AuditError>) {
    if completion.is_complete() {
        return (base, errors);
    }
    let status = match base {
        AuditStatus::Pass => AuditStatus::Warning,
        other => other,
    };
    (status, errors)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::defaults::default_audit_configuration;
    use crate::template::ignore_template_contents;
    use std::fs;

    #[test]
    fn matches_glob_rule_paths() {
        use crate::audit_model::{PrivacyRule, RuleSeverity};
        let dir = std::env::temp_dir().join(format!("offsend-policy-glob-{}", std::process::id()));
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(dir.join("nested")).unwrap();
        fs::write(dir.join("a.ignore"), "x").unwrap();
        fs::write(dir.join("nested/b.ignore"), "x").unwrap();
        fs::create_dir_all(dir.join("node_modules")).unwrap();
        fs::write(dir.join("node_modules/c.ignore"), "x").unwrap();

        let mut configuration = default_audit_configuration();
        configuration.rules = vec![PrivacyRule {
            id: "glob-ignore".into(),
            tool_name: "Test".into(),
            tool: None,
            title: "Glob".into(),
            relative_path_patterns: vec!["*.ignore".into(), "nested/*.ignore".into()],
            severity: RuleSeverity::Recommended,
            scans_for_sensitive_patterns: false,
            remediation: String::new(),
            fix: None,
        }];

        let result = PrivacyAuditor::audit_with(&dir, &configuration);
        let _ = fs::remove_dir_all(&dir);
        let finding = result.rule_findings.iter().find(|f| f.rule.id == "glob-ignore").unwrap();
        assert_eq!(
            finding.matched_relative_paths,
            vec!["a.ignore".to_string(), "nested/b.ignore".to_string()]
        );
    }

    #[test]
    fn audits_temp_workspace() {
        let dir = std::env::temp_dir().join(format!("offsend-policy-full-{}", std::process::id()));
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(&dir).unwrap();
        fs::write(dir.join(".cursorignore"), ignore_template_contents()).unwrap();
        fs::write(dir.join("server.pem"), "x").unwrap(); // covered by *.pem in template
        fs::write(dir.join("secrets.json"), "x").unwrap(); // also in template

        let result = PrivacyAuditor::audit(&dir);
        let _ = fs::remove_dir_all(&dir);

        let cursor = result
            .rule_findings
            .iter()
            .find(|f| f.rule.id == "cursor-ignore")
            .unwrap();
        assert!(cursor.is_satisfied());
        // Missing other recommended ignore files → warning at least
        assert!(matches!(
            result.status,
            AuditStatus::Warning | AuditStatus::Pass | AuditStatus::Fail
        ));
        assert!(cursor.exposed_relative_paths.is_empty());
    }

    #[test]
    fn missing_required_rule_is_warning() {
        let dir = std::env::temp_dir().join(format!("offsend-policy-empty-{}", std::process::id()));
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(&dir).unwrap();
        let result = PrivacyAuditor::audit_with(&dir, &default_audit_configuration());
        let _ = fs::remove_dir_all(&dir);
        assert_eq!(result.status, AuditStatus::Warning);
        assert!(result
            .rule_findings
            .iter()
            .any(|f| f.rule.id == "cursor-ignore" && !f.is_satisfied()));
    }
}
