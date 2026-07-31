//! Ignore-file materialization — port of Swift `OffsendIgnoreSyncService`.

use crate::audit_model::{AuditConfiguration, FixStrategy};
use crate::config::{CONFIG_FILENAME, OffsendProjectConfig, ToolId};
use crate::defaults::default_audit_configuration;
use crate::managed_block::{ManagedIgnoreBlock, UpsertResult};
use crate::template::{
    DEFAULT_IGNORE_PATTERNS, IGNORE_TEMPLATE_HEADER, ignore_template_contents, managed_seed_contents,
};
use std::collections::HashSet;
use std::fs;
use std::path::{Path, PathBuf};

pub const IGNORE_FILES_SECTION: &str = "ignore-files";
pub const HOOKS_SECTION: &str = "hooks";

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct IgnoreSyncReport {
    pub directory_path: PathBuf,
    pub dry_run: bool,
    pub patterns: Vec<String>,
    pub commit_ignore_files: bool,
    pub created_relative_paths: Vec<String>,
    pub updated_relative_paths: Vec<String>,
    pub unchanged_relative_paths: Vec<String>,
    pub gitignore_updated: bool,
    pub gitignore_path: Option<PathBuf>,
    pub exclude_updated: bool,
    pub exclude_path: Option<PathBuf>,
    pub errors: Vec<String>,
}

impl IgnoreSyncReport {
    pub fn has_errors(&self) -> bool {
        !self.errors.is_empty()
    }
}

pub struct IgnoreSyncService;

impl IgnoreSyncService {
    /// Relative paths of AI ignore files Offsend manages.
    pub fn managed_ignore_relative_paths(
        configuration: &AuditConfiguration,
        tools: Option<&HashSet<ToolId>>,
    ) -> Vec<String> {
        let cfg = configuration.clone().filtered(tools);
        let mut paths: Vec<String> = cfg
            .rules
            .iter()
            .filter(|r| r.scans_for_sensitive_patterns)
            .filter_map(|r| r.fix.as_ref().map(|f| f.relative_path.clone()))
            .collect();
        paths.sort();
        paths.dedup();
        paths
    }

    /// Exact relative paths of managed editor rule files (`keepManagedContent`).
    pub fn managed_rule_relative_paths(
        configuration: &AuditConfiguration,
        tools: Option<&HashSet<ToolId>>,
    ) -> Vec<String> {
        let cfg = configuration.clone().filtered(tools);
        let mut paths: Vec<String> = cfg
            .rules
            .iter()
            .filter_map(|r| {
                let fix = r.fix.as_ref()?;
                if fix.strategy == FixStrategy::KeepManagedContent {
                    Some(fix.relative_path.clone())
                } else {
                    None
                }
            })
            .collect();
        paths.sort();
        paths.dedup();
        paths
    }

    pub fn run(directory: &Path, dry_run: bool) -> IgnoreSyncReport {
        let root = materialization_root(directory);
        if !root.is_dir() {
            return IgnoreSyncReport {
                directory_path: root,
                dry_run,
                patterns: vec![],
                commit_ignore_files: false,
                created_relative_paths: vec![],
                updated_relative_paths: vec![],
                unchanged_relative_paths: vec![],
                gitignore_updated: false,
                gitignore_path: None,
                exclude_updated: false,
                exclude_path: None,
                errors: vec![format!("Directory does not exist: {}", directory.display())],
            };
        }

        let config = match OffsendProjectConfig::load_from_path(&root.join(CONFIG_FILENAME)) {
            Ok(Some(cfg)) => cfg,
            Ok(None) => {
                return IgnoreSyncReport {
                    directory_path: root.clone(),
                    dry_run,
                    patterns: vec![],
                    commit_ignore_files: false,
                    created_relative_paths: vec![],
                    updated_relative_paths: vec![],
                    unchanged_relative_paths: vec![],
                    gitignore_updated: false,
                    gitignore_path: None,
                    exclude_updated: false,
                    exclude_path: None,
                    errors: vec![format!(
                        "No {CONFIG_FILENAME} in {}. Run `offsend init` first.",
                        root.display()
                    )],
                };
            }
            Err(e) => {
                return IgnoreSyncReport {
                    directory_path: root,
                    dry_run,
                    patterns: vec![],
                    commit_ignore_files: false,
                    created_relative_paths: vec![],
                    updated_relative_paths: vec![],
                    unchanged_relative_paths: vec![],
                    gitignore_updated: false,
                    gitignore_path: None,
                    exclude_updated: false,
                    exclude_path: None,
                    errors: vec![format!("Failed to load {CONFIG_FILENAME}: {e}")],
                };
            }
        };

        let patterns = config
            .ignore
            .as_ref()
            .map(|i| i.patterns_or_empty().to_vec())
            .unwrap_or_default();
        let commit = config
            .ignore
            .as_ref()
            .map(|i| i.commits_ignore_files())
            .unwrap_or(false);
        let tools = config.ignore.as_ref().and_then(|i| i.tool_ids());

        Self::run_with(
            &root,
            &patterns,
            commit,
            tools.as_ref(),
            dry_run,
            &default_audit_configuration(),
        )
    }

    pub fn run_with(
        root: &Path,
        raw_patterns: &[String],
        commit_ignore_files: bool,
        tools: Option<&HashSet<ToolId>>,
        dry_run: bool,
        configuration: &AuditConfiguration,
    ) -> IgnoreSyncReport {
        let mut errors = Vec::new();
        let patterns = ManagedIgnoreBlock::normalize_patterns(raw_patterns);
        let targets = Self::managed_ignore_relative_paths(configuration, tools);

        let mut created = Vec::new();
        let mut updated = Vec::new();
        let mut unchanged = Vec::new();

        for relative_path in &targets {
            let path = root.join(relative_path);
            let file_exists = path.is_file();
            let existing = if file_exists {
                fs::read_to_string(&path).ok()
            } else {
                None
            };
            let seed = seed_for_managed_upsert(existing.as_deref(), &patterns);
            let (contents, result) =
                ManagedIgnoreBlock::upsert(&patterns, Some(seed.as_str()), None);

            match &result {
                UpsertResult::Malformed(message) => {
                    errors.push(format!("{relative_path}: {message}"));
                    continue;
                }
                UpsertResult::Created | UpsertResult::Updated | UpsertResult::Unchanged => {}
            }

            let needs_write = !file_exists || result != UpsertResult::Unchanged;
            if !needs_write {
                unchanged.push(relative_path.clone());
                continue;
            }

            if dry_run {
                if file_exists {
                    updated.push(relative_path.clone());
                } else {
                    created.push(relative_path.clone());
                }
                continue;
            }

            if let Err(e) = write_file(&contents, &path) {
                let verb = if file_exists { "update" } else { "create" };
                errors.push(format!("Failed to {verb} {relative_path}: {e}"));
            } else if file_exists {
                updated.push(relative_path.clone());
            } else {
                created.push(relative_path.clone());
            }
        }

        let gitignore = if commit_ignore_files {
            gitignore_remove_section(root, IGNORE_FILES_SECTION, dry_run)
        } else {
            let rule_paths = Self::managed_rule_relative_paths(configuration, tools);
            let mut all = targets.clone();
            all.extend(rule_paths);
            all.sort();
            all.dedup();
            gitignore_upsert_patterns(root, &all, IGNORE_FILES_SECTION, dry_run)
        };
        errors.extend(gitignore.errors);

        let exclude = exclude_remove_section(root, IGNORE_FILES_SECTION, dry_run);
        errors.extend(exclude.errors);

        created.sort();
        updated.sort();
        unchanged.sort();

        IgnoreSyncReport {
            directory_path: root.to_path_buf(),
            dry_run,
            patterns,
            commit_ignore_files,
            created_relative_paths: created,
            updated_relative_paths: updated,
            unchanged_relative_paths: unchanged,
            gitignore_updated: gitignore.updated,
            gitignore_path: Some(gitignore.path),
            exclude_updated: exclude.updated,
            exclude_path: Some(exclude.path),
            errors,
        }
    }
}

struct FileReport {
    path: PathBuf,
    updated: bool,
    errors: Vec<String>,
}

fn gitignore_upsert_patterns(
    root: &Path,
    patterns: &[String],
    section: &str,
    dry_run: bool,
) -> FileReport {
    let path = root.join(".gitignore");
    let existing = if path.is_file() {
        fs::read_to_string(&path).ok()
    } else {
        None
    };
    let (contents, result) =
        ManagedIgnoreBlock::upsert(patterns, existing.as_deref(), Some(section));
    match result {
        UpsertResult::Malformed(message) => FileReport {
            path,
            updated: false,
            errors: vec![message],
        },
        UpsertResult::Unchanged => FileReport {
            path,
            updated: false,
            errors: vec![],
        },
        UpsertResult::Created | UpsertResult::Updated => {
            if dry_run {
                FileReport {
                    path,
                    updated: true,
                    errors: vec![],
                }
            } else if let Err(e) = write_file(&contents, &path) {
                FileReport {
                    path: path.clone(),
                    updated: false,
                    errors: vec![format!("Failed to update {}: {e}", path.display())],
                }
            } else {
                FileReport {
                    path,
                    updated: true,
                    errors: vec![],
                }
            }
        }
    }
}

fn gitignore_remove_section(root: &Path, section: &str, dry_run: bool) -> FileReport {
    let path = root.join(".gitignore");
    let Ok(existing) = fs::read_to_string(&path) else {
        return FileReport {
            path,
            updated: false,
            errors: vec![],
        };
    };
    let Some(cleaned) = ManagedIgnoreBlock::removing(Some(section), &existing) else {
        return FileReport {
            path,
            updated: false,
            errors: vec![],
        };
    };
    if dry_run {
        return FileReport {
            path,
            updated: true,
            errors: vec![],
        };
    }
    if let Err(e) = write_file(&cleaned, &path) {
        FileReport {
            path: path.clone(),
            updated: false,
            errors: vec![format!("Failed to update {}: {e}", path.display())],
        }
    } else {
        FileReport {
            path,
            updated: true,
            errors: vec![],
        }
    }
}

fn exclude_remove_section(root: &Path, section: &str, dry_run: bool) -> FileReport {
    let path = root.join(".git/info/exclude");
    let Ok(existing) = fs::read_to_string(&path) else {
        return FileReport {
            path: path.clone(),
            updated: false,
            errors: vec![],
        };
    };
    let Some(cleaned) = ManagedIgnoreBlock::removing(Some(section), &existing) else {
        return FileReport {
            path,
            updated: false,
            errors: vec![],
        };
    };
    if dry_run {
        return FileReport {
            path,
            updated: true,
            errors: vec![],
        };
    }
    if let Err(e) = write_file(&cleaned, &path) {
        FileReport {
            path: path.clone(),
            updated: false,
            errors: vec![format!("Failed to update {}: {e}", path.display())],
        }
    } else {
        FileReport {
            path,
            updated: true,
            errors: vec![],
        }
    }
}

fn seed_for_managed_upsert(existing: Option<&str>, patterns: &[String]) -> String {
    if patterns.is_empty() {
        return existing
            .map(str::to_string)
            .unwrap_or_else(ignore_template_contents);
    }
    let Some(existing) = existing else {
        return managed_seed_contents();
    };
    if ManagedIgnoreBlock::patterns(existing, None).is_some() {
        return existing.to_string();
    }
    strip_patterns_owned_by_managed_block(existing, patterns)
}

fn strip_patterns_owned_by_managed_block(existing: &str, patterns: &[String]) -> String {
    let mut owned_src: Vec<String> = patterns.to_vec();
    owned_src.extend(DEFAULT_IGNORE_PATTERNS.iter().map(|s| (*s).to_string()));
    let owned: HashSet<String> = ManagedIgnoreBlock::normalize_patterns(&owned_src)
        .into_iter()
        .collect();

    let mut kept: Vec<String> = Vec::new();
    let mut saw_header = false;
    for line in existing.split('\n') {
        let trimmed = line.trim();
        if trimmed.is_empty() {
            continue;
        }
        if trimmed == IGNORE_TEMPLATE_HEADER {
            saw_header = true;
            kept.push(IGNORE_TEMPLATE_HEADER.to_string());
            continue;
        }
        if trimmed.starts_with('#') {
            kept.push(line.to_string());
            continue;
        }
        if owned.contains(trimmed) {
            continue;
        }
        kept.push(line.to_string());
    }
    if kept.is_empty() {
        return managed_seed_contents();
    }
    if !saw_header {
        kept.insert(0, IGNORE_TEMPLATE_HEADER.to_string());
    }
    kept.join("\n") + "\n"
}

fn write_file(contents: &str, path: &Path) -> std::io::Result<()> {
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)?;
    }
    // Avoid temp names starting with ".." (e.g. for `.cursorignore`) — some
    // path normalizers treat that as a parent-directory escape.
    let tmp = path.with_file_name(format!(
        ".offsend-write-{}-{}.tmp",
        std::process::id(),
        path.file_name()
            .and_then(|s| s.to_str())
            .unwrap_or("out")
            .replace('.', "_")
    ));
    fs::write(&tmp, contents)?;
    fs::rename(&tmp, path).map_err(|e| {
        let _ = fs::remove_file(&tmp);
        e
    })?;
    Ok(())
}

fn materialization_root(start: &Path) -> PathBuf {
    // Match Swift `GitRepositoryResolver.repositoryRoot`: walk parents for `.git`.
    // Do not use `git rev-parse` — it can escape unexpected layouts; missing `.git`
    // means materialize in `start` itself.
    let mut candidate = if start.is_dir() {
        start.to_path_buf()
    } else {
        start
            .parent()
            .map(Path::to_path_buf)
            .unwrap_or_else(|| start.to_path_buf())
    };
    loop {
        if candidate.join(".git").exists() {
            return candidate;
        }
        if !candidate.pop() {
            break;
        }
    }
    start.to_path_buf()
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::time::{SystemTime, UNIX_EPOCH};

    fn tmp_dir() -> PathBuf {
        let nanos = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        let dir = std::env::temp_dir().join(format!("offsend-ignore-sync-{nanos}"));
        fs::create_dir_all(&dir).unwrap();
        dir
    }

    #[test]
    fn creates_ignore_files_and_gitignore_section() {
        let dir = tmp_dir();
        // Isolate from any parent `.git` (e.g. nested temp under a checkout).
        fs::create_dir_all(dir.join(".git")).unwrap();
        let yml = r#"
version: 1
ignore:
  commit: false
  tools: [cursor]
  patterns:
    - "*.env"
    - "local-secrets/"
"#;
        fs::write(dir.join(".offsend.yml"), yml).unwrap();

        let report = IgnoreSyncService::run(&dir, false);
        assert!(!report.has_errors(), "{:?}", report.errors);
        assert!(report.created_relative_paths.contains(&".cursorignore".into()));
        assert!(report
            .created_relative_paths
            .contains(&".cursorindexingignore".into()));
        assert!(!report
            .created_relative_paths
            .iter()
            .any(|p| p.contains("claude")));

        let cursor = fs::read_to_string(dir.join(".cursorignore")).unwrap();
        assert!(cursor.contains("# >>> offsend managed"));
        assert!(cursor.contains("*.env"));
        assert!(cursor.contains("local-secrets/"));

        let gi = fs::read_to_string(dir.join(".gitignore")).unwrap();
        assert!(gi.contains("# >>> offsend managed: ignore-files"));
        assert!(gi.contains(".cursorignore"));
        assert!(gi.contains(".cursor/rules/offsend_privacy.mdc"));

        // Idempotent
        let again = IgnoreSyncService::run(&dir, false);
        assert!(!again.has_errors());
        assert!(again.created_relative_paths.is_empty());
        assert!(again.updated_relative_paths.is_empty());
        assert!(again
            .unchanged_relative_paths
            .contains(&".cursorignore".into()));

        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn commit_true_removes_gitignore_section() {
        let dir = tmp_dir();
        fs::create_dir_all(dir.join(".git")).unwrap();
        fs::write(
            dir.join(".gitignore"),
            "# >>> offsend managed: ignore-files\n.cursorignore\n# <<< offsend managed: ignore-files\n",
        )
        .unwrap();
        fs::write(
            dir.join(".offsend.yml"),
            "version: 1\nignore:\n  commit: true\n  tools: [cursor]\n  patterns:\n    - \"*.env\"\n",
        )
        .unwrap();

        let report = IgnoreSyncService::run(&dir, false);
        assert!(!report.has_errors(), "{:?}", report.errors);
        assert!(report.gitignore_updated);
        let gi = fs::read_to_string(dir.join(".gitignore")).unwrap();
        assert!(!gi.contains("offsend managed: ignore-files"));

        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn missing_config_errors() {
        let dir = tmp_dir();
        fs::create_dir_all(dir.join(".git")).unwrap();
        let report = IgnoreSyncService::run(&dir, false);
        assert!(report.has_errors(), "{:?}", report);
        assert!(report.errors[0].contains(".offsend.yml"));
        let _ = fs::remove_dir_all(&dir);
    }
}
