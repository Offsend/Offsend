//! Privacy fix applicator — port of Swift `AIWorkspacePrivacyFixer`
//! (without NSFileCoordinator; direct filesystem writes).

use crate::audit_model::{
    AuditConfiguration, AuditError, AuditResult, FileFix, FixStrategy, RuleSeverity,
};
use crate::fix_planner::{FixSelection, PrivacyFixPlanner};
use crate::ignore::IgnoreFileParser;
use crate::template::IGNORE_TEMPLATE_HEADER;
use std::collections::HashSet;
use std::fs;
use std::path::{Component, Path, PathBuf};

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct FixResult {
    pub created_relative_paths: Vec<String>,
    pub updated_relative_paths: Vec<String>,
    pub errors: Vec<AuditError>,
}

impl FixResult {
    pub fn did_change_files(&self) -> bool {
        !self.created_relative_paths.is_empty() || !self.updated_relative_paths.is_empty()
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum AppendOutcome {
    Created(String),
    Updated(String),
    Unchanged(String),
    Failed(AuditError),
}

#[derive(Debug, Clone, PartialEq, Eq)]
enum FileWriteOutcome {
    Created(String),
    Updated(String),
    Unchanged,
    Failed(AuditError),
}

#[derive(Debug, Clone, PartialEq, Eq)]
enum LineAppendOutcome {
    Created(String),
    Updated(String),
    Unchanged,
    Failed(AuditError),
}

pub struct PrivacyFixer;

impl PrivacyFixer {
    pub fn fix(
        result: &AuditResult,
        configuration: &AuditConfiguration,
        selection: Option<&FixSelection>,
    ) -> FixResult {
        let root = result.directory.as_path();
        if !is_writable_directory(root) {
            return FixResult {
                created_relative_paths: vec![],
                updated_relative_paths: vec![],
                errors: vec![AuditError {
                    id: "directory-not-writable".into(),
                    message: "The selected directory is not writable.".into(),
                }],
            };
        }

        let mut created_relative_paths: HashSet<String> = HashSet::new();
        let mut updated_relative_paths: HashSet<String> = HashSet::new();
        let mut errors: Vec<AuditError> = Vec::new();

        for finding in &result.rule_findings {
            if finding.rule.severity == RuleSeverity::Informational {
                continue;
            }
            if let Some(selection) = selection {
                if !selection.rule_ids.contains(&finding.rule.id) {
                    continue;
                }
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

            let outcome = if !finding.is_satisfied() {
                apply_fix(fix, root)
            } else if fix.strategy == FixStrategy::KeepManagedContent {
                // Satisfied rule whose managed file may have drifted. Restore only when
                // the managed file itself exists: a rule satisfied by a legacy path
                // must not gain a duplicate.
                restore_managed_content(fix, root, true)
            } else {
                continue;
            };

            match outcome {
                FileWriteOutcome::Created(path) => {
                    created_relative_paths.insert(path);
                }
                FileWriteOutcome::Updated(path) => {
                    updated_relative_paths.insert(path);
                }
                FileWriteOutcome::Unchanged => {}
                FileWriteOutcome::Failed(error) => errors.push(error),
            }
        }

        let missing_patterns: Vec<_> = result
            .missing_sensitive_patterns()
            .into_iter()
            .filter(|finding| match selection {
                None => true,
                Some(sel) => sel.pattern_ids.contains(&finding.pattern.id),
            })
            .collect();

        if !missing_patterns.is_empty() {
            let lines: Vec<String> = missing_patterns
                .iter()
                .map(|f| f.pattern.canonical_ignore_line().to_string())
                .collect();
            let target_paths = PrivacyFixPlanner::pattern_target_relative_paths(
                result,
                configuration,
                selection,
                &created_relative_paths,
            );
            if target_paths.is_empty() {
                errors.push(AuditError {
                    id: "no-pattern-target-files".into(),
                    message: "Select at least one policy ignore file (for example .cursorignore) to apply the chosen sensitive patterns.".into(),
                });
            } else {
                for relative_path in target_paths {
                    match append_missing_lines(&lines, &relative_path, root) {
                        LineAppendOutcome::Created(path) => {
                            created_relative_paths.insert(path);
                        }
                        LineAppendOutcome::Updated(path) => {
                            updated_relative_paths.insert(path);
                        }
                        LineAppendOutcome::Unchanged => {}
                        LineAppendOutcome::Failed(error) => errors.push(error),
                    }
                }
            }
        }

        let mut created: Vec<String> = created_relative_paths.into_iter().collect();
        created.sort();
        let mut updated: Vec<String> = updated_relative_paths.into_iter().collect();
        updated.sort();

        FixResult {
            created_relative_paths: created,
            updated_relative_paths: updated,
            errors,
        }
    }

        /// Appends the given ignore lines to one file, skipping lines already present.
    /// When the file is missing it is created — seeded with `template_contents_if_missing`
    /// when provided, otherwise with just the standard header.
    pub fn append_ignore_lines(
        lines: &[String],
        relative_path: &str,
        root: &Path,
        template_contents_if_missing: Option<&str>,
    ) -> AppendOutcome {
        if let Some(template) = template_contents_if_missing {
            if let Some(url) = safe_path(root, relative_path) {
                if !url.exists() {
                    if let FileWriteOutcome::Failed(error) =
                        write_contents(template, &url, relative_path, true)
                    {
                        return AppendOutcome::Failed(error);
                    }
                    if let LineAppendOutcome::Failed(error) =
                        append_missing_lines(lines, relative_path, root)
                    {
                        return AppendOutcome::Failed(error);
                    }
                    return AppendOutcome::Created(relative_path.to_string());
                }
            }
        }

        match append_missing_lines(lines, relative_path, root) {
            LineAppendOutcome::Created(path) => AppendOutcome::Created(path),
            LineAppendOutcome::Updated(path) => AppendOutcome::Updated(path),
            LineAppendOutcome::Unchanged => AppendOutcome::Unchanged(relative_path.to_string()),
            LineAppendOutcome::Failed(error) => AppendOutcome::Failed(error),
        }
    }
}

fn apply_fix(fix: &FileFix, root: &Path) -> FileWriteOutcome {
    match fix.strategy {
        FixStrategy::CreateIfMissing => create_file_if_missing(fix, root),
        FixStrategy::MergeLines => merge_lines(fix, root),
        FixStrategy::KeepManagedContent => restore_managed_content(fix, root, false),
    }
}

fn restore_managed_content(
    fix: &FileFix,
    root: &Path,
    only_if_file_exists: bool,
) -> FileWriteOutcome {
    let Some(url) = safe_path(root, &fix.relative_path) else {
        return FileWriteOutcome::Failed(invalid_path_error(&fix.relative_path));
    };

    if let Some(parent) = url.parent() {
        if let Err(error) = fs::create_dir_all(parent) {
            return FileWriteOutcome::Failed(AuditError {
                id: "restore-managed-file-failed".into(),
                message: format!("Could not restore {}: {error}", fix.relative_path),
            });
        }
    }

    let expected = normalized_contents(&fix.contents);
    let exists = url.exists();
    if !exists && only_if_file_exists {
        return FileWriteOutcome::Unchanged;
    }
    if exists {
        if let Ok(existing) = fs::read_to_string(&url) {
            if normalized_contents(&existing) == expected {
                return FileWriteOutcome::Unchanged;
            }
        }
    }

    match fs::write(&url, &expected) {
        Ok(()) => {
            if exists {
                FileWriteOutcome::Updated(fix.relative_path.clone())
            } else {
                FileWriteOutcome::Created(fix.relative_path.clone())
            }
        }
        Err(error) => FileWriteOutcome::Failed(AuditError {
            id: "restore-managed-file-failed".into(),
            message: format!("Could not restore {}: {error}", fix.relative_path),
        }),
    }
}

fn create_file_if_missing(fix: &FileFix, root: &Path) -> FileWriteOutcome {
    let Some(url) = safe_path(root, &fix.relative_path) else {
        return FileWriteOutcome::Failed(invalid_path_error(&fix.relative_path));
    };

    if let Some(parent) = url.parent() {
        if let Err(error) = fs::create_dir_all(parent) {
            return FileWriteOutcome::Failed(AuditError {
                id: "create-file-failed".into(),
                message: format!("Could not create {}: {error}", fix.relative_path),
            });
        }
    }

    if url.exists() {
        return FileWriteOutcome::Unchanged;
    }

    match fs::write(&url, normalized_contents(&fix.contents)) {
        Ok(()) => FileWriteOutcome::Created(fix.relative_path.clone()),
        Err(error) => FileWriteOutcome::Failed(AuditError {
            id: "create-file-failed".into(),
            message: format!("Could not create {}: {error}", fix.relative_path),
        }),
    }
}

fn merge_lines(fix: &FileFix, root: &Path) -> FileWriteOutcome {
    let Some(url) = safe_path(root, &fix.relative_path) else {
        return FileWriteOutcome::Failed(invalid_path_error(&fix.relative_path));
    };

    if !url.exists() {
        return write_contents(&fix.contents, &url, &fix.relative_path, true);
    }

    let lines = IgnoreFileParser::pattern_lines(&fix.contents);
    if lines.is_empty() {
        return FileWriteOutcome::Unchanged;
    }

    match append_missing_lines(&lines, &fix.relative_path, root) {
        LineAppendOutcome::Created(path) => FileWriteOutcome::Created(path),
        LineAppendOutcome::Updated(path) => FileWriteOutcome::Updated(path),
        LineAppendOutcome::Unchanged => FileWriteOutcome::Unchanged,
        LineAppendOutcome::Failed(error) => FileWriteOutcome::Failed(error),
    }
}

fn append_missing_lines(lines: &[String], relative_path: &str, root: &Path) -> LineAppendOutcome {
    if lines.is_empty() {
        return LineAppendOutcome::Unchanged;
    }
    let Some(url) = safe_path(root, relative_path) else {
        return LineAppendOutcome::Failed(invalid_path_error(relative_path));
    };

    if let Some(parent) = url.parent() {
        if let Err(error) = fs::create_dir_all(parent) {
            return LineAppendOutcome::Failed(AuditError {
                id: "append-patterns-failed".into(),
                message: format!("Could not update {relative_path}: {error}"),
            });
        }
    }

    let (existing_contents, did_create_file) = if url.exists() {
        match fs::read_to_string(&url) {
            Ok(contents) => (contents, false),
            Err(error) => {
                return LineAppendOutcome::Failed(AuditError {
                    id: "append-patterns-failed".into(),
                    message: format!("Could not update {relative_path}: {error}"),
                });
            }
        }
    } else {
        (format!("{IGNORE_TEMPLATE_HEADER}\n"), true)
    };

    let existing_patterns = IgnoreFileParser::patterns(&existing_contents);
    let missing_lines: Vec<&str> = lines
        .iter()
        .filter(|line| !existing_patterns.contains(line.as_str()))
        .map(String::as_str)
        .collect();
    if missing_lines.is_empty() {
        return LineAppendOutcome::Unchanged;
    }

    let separator = if existing_contents.ends_with('\n') {
        ""
    } else {
        "\n"
    };
    let updated_contents =
        existing_contents + separator + &missing_lines.join("\n") + "\n";

    match fs::write(&url, updated_contents) {
        Ok(()) => {
            if did_create_file {
                LineAppendOutcome::Created(relative_path.to_string())
            } else {
                LineAppendOutcome::Updated(relative_path.to_string())
            }
        }
        Err(error) => LineAppendOutcome::Failed(AuditError {
            id: "append-patterns-failed".into(),
            message: format!("Could not update {relative_path}: {error}"),
        }),
    }
}

fn write_contents(
    contents: &str,
    url: &Path,
    relative_path: &str,
    did_create_file: bool,
) -> FileWriteOutcome {
    if let Some(parent) = url.parent() {
        if let Err(error) = fs::create_dir_all(parent) {
            return FileWriteOutcome::Failed(AuditError {
                id: "create-file-failed".into(),
                message: format!("Could not create {relative_path}: {error}"),
            });
        }
    }

    if url.exists() {
        return FileWriteOutcome::Unchanged;
    }

    match fs::write(url, normalized_contents(contents)) {
        Ok(()) => {
            if did_create_file {
                FileWriteOutcome::Created(relative_path.to_string())
            } else {
                FileWriteOutcome::Updated(relative_path.to_string())
            }
        }
        Err(error) => FileWriteOutcome::Failed(AuditError {
            id: "create-file-failed".into(),
            message: format!("Could not create {relative_path}: {error}"),
        }),
    }
}

fn is_writable_directory(path: &Path) -> bool {
    match fs::metadata(path) {
        Ok(meta) if meta.is_dir() => !meta.permissions().readonly(),
        _ => false,
    }
}

/// Reject absolute paths and `..` escapes under `root`.
fn safe_path(root: &Path, relative: &str) -> Option<PathBuf> {
    if relative.is_empty() {
        return None;
    }
    let rel = Path::new(relative);
    if rel.is_absolute() {
        return None;
    }
    for component in rel.components() {
        match component {
            Component::Normal(_) | Component::CurDir => {}
            Component::ParentDir | Component::RootDir | Component::Prefix(_) => return None,
        }
    }
    let joined = root.join(relative);
    let root_canon = lexical_normalize(root);
    let joined_canon = lexical_normalize(&joined);
    if joined_canon == root_canon || joined_canon.starts_with(&root_canon) {
        Some(joined)
    } else {
        None
    }
}

fn lexical_normalize(path: &Path) -> PathBuf {
    let mut out = PathBuf::new();
    for component in path.components() {
        match component {
            Component::ParentDir => {
                out.pop();
            }
            Component::CurDir => {}
            other => out.push(other.as_os_str()),
        }
    }
    out
}

fn normalized_contents(contents: &str) -> String {
    if contents.ends_with('\n') {
        contents.to_string()
    } else {
        format!("{contents}\n")
    }
}

fn invalid_path_error(relative_path: &str) -> AuditError {
    AuditError {
        id: "invalid-fix-path".into(),
        message: format!("The fix path is outside the selected directory: {relative_path}"),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::audit_model::{ExposureScanCompletion, ExposureScanLimits, PrivacyRule};
    use std::collections::HashSet;

    fn temp_dir(name: &str) -> PathBuf {
        let dir = std::env::temp_dir().join(format!(
            "offsend-policy-fixer-{}-{}",
            name,
            std::process::id()
        ));
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(&dir).unwrap();
        dir
    }

    #[test]
    fn create_if_missing_creates_file() {
        let dir = temp_dir("create-if-missing");
        let fix = FileFix {
            relative_path: ".cursor/rules/offsend_privacy.mdc".into(),
            contents: "hello\n".into(),
            strategy: FixStrategy::CreateIfMissing,
        };
        let rule = PrivacyRule {
            id: "cursor-project-rules".into(),
            tool_name: "Cursor".into(),
            tool: None,
            title: "Cursor project rules".into(),
            relative_path_patterns: vec![".cursor/rules/offsend_privacy.mdc".into()],
            severity: RuleSeverity::Recommended,
            scans_for_sensitive_patterns: false,
            remediation: "".into(),
            fix: Some(fix.clone()),
        };
        let configuration = AuditConfiguration {
            rules: vec![rule.clone()],
            sensitive_patterns: vec![],
            additional_skipped_directory_names: HashSet::new(),
            exposure_scan_limits: ExposureScanLimits::UNLIMITED,
        };
        let result = AuditResult {
            directory: dir.clone(),
            status: crate::audit_model::AuditStatus::Warning,
            rule_findings: vec![crate::audit_model::RuleFinding {
                rule,
                matched_relative_paths: vec![],
                exposed_relative_paths: vec![],
            }],
            sensitive_pattern_findings: vec![],
            errors: vec![],
            exposure_index: None,
            exposure_scan_completion: ExposureScanCompletion::Complete,
        };

        let fix_result = PrivacyFixer::fix(&result, &configuration, None);
        let path = dir.join(".cursor/rules/offsend_privacy.mdc");
        let contents = fs::read_to_string(&path).unwrap();
        let _ = fs::remove_dir_all(&dir);

        assert!(fix_result.errors.is_empty(), "{:?}", fix_result.errors);
        assert!(fix_result
            .created_relative_paths
            .contains(&".cursor/rules/offsend_privacy.mdc".to_string()));
        assert_eq!(contents, "hello\n");
    }

    #[test]
    fn append_patterns_skips_existing() {
        let dir = temp_dir("append-skips");
        fs::write(dir.join(".cursorignore"), ".env*\n*.pem\n").unwrap();

        let outcome = PrivacyFixer::append_ignore_lines(
            &["*.pem".into(), "*.key".into()],
            ".cursorignore",
            &dir,
            None,
        );
        let contents = fs::read_to_string(dir.join(".cursorignore")).unwrap();
        let _ = fs::remove_dir_all(&dir);

        assert_eq!(outcome, AppendOutcome::Updated(".cursorignore".into()));
        assert_eq!(contents.matches("*.pem").count(), 1);
        assert!(contents.contains("*.key"));
        assert!(contents.contains(".env*"));
    }

    #[test]
    fn safe_path_rejects_absolute_and_parent_escapes() {
        let root = PathBuf::from("/tmp/offsend-root");
        assert!(safe_path(&root, "/etc/passwd").is_none());
        assert!(safe_path(&root, "../outside").is_none());
        assert!(safe_path(&root, "ok/file.txt").is_some());
        assert!(safe_path(&root, "nested/../ok.txt").is_none());
    }
}
