//! Verify that declared `hooks.enabled` matches installed git / AI-editor hooks.

use crate::hook_ai;
use crate::hook_git::{self, HookState};
use offsend_policy::OffsendProjectConfig;
use std::path::Path;

#[derive(Debug)]
pub struct Finding {
    pub id: String,
    pub message: String,
    pub is_failure: bool,
}

/// Whether `doctor` / `check --policy` should require **git** hooks.
/// No `.offsend.yml` → do not enforce (nothing declared).
/// Project AI-editor hooks are not required in CI (`check --policy`); doctor
/// reports them separately from user-level hooks.
pub fn hooks_required(config: Option<&OffsendProjectConfig>) -> bool {
    config.map(OffsendProjectConfig::hooks_enabled).unwrap_or(false)
}

/// Whether `sync` should install hooks.
/// No `.offsend.yml` → install (preserve previous behavior); explicit `false` skips.
pub fn should_install(config: Option<&OffsendProjectConfig>) -> bool {
    config.map(OffsendProjectConfig::hooks_enabled).unwrap_or(true)
}

/// Git-hook findings for `check --policy` (CI) and doctor.
/// Missing project AI-editor files are not included — user-level hooks cover the machine.
pub fn git_findings(root: &Path, config: Option<&OffsendProjectConfig>) -> Vec<Finding> {
    if !hooks_required(config) {
        return Vec::new();
    }

    let mut findings = Vec::new();
    let repo = hook_git::resolve_repo_root(root).unwrap_or_else(|_| root.to_path_buf());

    let git_names = config
        .map(|c| c.git_hooks())
        .unwrap_or_else(|| vec!["pre-commit".into()]);

    if let Some(hooks) = config.and_then(|c| c.hooks.as_ref()) {
        for name in hooks.unknown_git_hooks() {
            findings.push(Finding {
                id: "git-hook".into(),
                message: format!(
                    "hooks.git lists unsupported hook {name:?}. Supported: pre-commit, post-merge."
                ),
                is_failure: true,
            });
        }
    }

    match hook_git::parse_kinds(&git_names) {
        Ok(kinds) => {
            if kinds.is_empty() && git_names.is_empty() {
                // Explicit empty list — no git hooks required.
            } else {
                for kind in kinds {
                    match hook_git::status(&repo, kind) {
                        Ok(status) => match status.state {
                            HookState::Installed => {}
                            HookState::NotInstalled => findings.push(Finding {
                                id: format!("git-{}", kind.as_str()),
                                message: format!(
                                    "hooks.enabled is true but git {} hook is not installed. Run: offsend sync",
                                    kind.as_str()
                                ),
                                is_failure: true,
                            }),
                            HookState::Modified => findings.push(Finding {
                                id: format!("git-{}", kind.as_str()),
                                message: format!(
                                    "hooks.enabled is true but {} is not Offsend-managed. Run: offsend hook install --target git --force",
                                    status.hook_path.display()
                                ),
                                is_failure: true,
                            }),
                        },
                        Err(_) => findings.push(Finding {
                            id: format!("git-{}", kind.as_str()),
                            message: format!(
                                "hooks.enabled is true but this path is not a git repository — cannot install {}.",
                                kind.as_str()
                            ),
                            is_failure: true,
                        }),
                    }
                }
            }
        }
        Err(e) => findings.push(Finding {
            id: "git-hook".into(),
            message: e.to_string(),
            is_failure: true,
        }),
    }

    findings
}

/// Project-level AI-editor hook status for doctor (warn, not CI fail).
pub fn ai_project_findings(root: &Path, config: Option<&OffsendProjectConfig>) -> Vec<Finding> {
    if !hooks_required(config) {
        return Vec::new();
    }

    let mut findings = Vec::new();
    let repo = hook_git::resolve_repo_root(root).unwrap_or_else(|_| root.to_path_buf());
    let home = dirs_home();

    for target in hook_ai::detected_targets(&repo, &home) {
        if !hook_ai::is_installed(target, &repo) {
            findings.push(Finding {
                id: format!("{}-hook", target.as_str()),
                message: format!(
                    "project {} hooks are not installed (user-level hooks from `offsend setup` cover this machine). Optional: offsend hook install --target {}",
                    target.as_str(),
                    target.as_str()
                ),
                is_failure: false,
            });
        }
    }

    for target in hook_ai::ALL_TARGETS {
        let path = target.config_path(&repo);
        if path.is_file() && !hook_ai::is_installed(target, &repo) {
            if findings
                .iter()
                .any(|f| f.id == format!("{}-hook", target.as_str()))
            {
                continue;
            }
            findings.push(Finding {
                id: format!("{}-hook", target.as_str()),
                message: format!(
                    "{} exists without Offsend managed marker. Run: offsend hook install --target {}",
                    path.display(),
                    target.as_str()
                ),
                is_failure: false,
            });
        }
    }

    findings
}

/// Git findings (fail) plus project AI-editor findings (warn). Used by doctor.
pub fn findings(root: &Path, config: Option<&OffsendProjectConfig>) -> Vec<Finding> {
    let mut out = git_findings(root, config);
    out.extend(ai_project_findings(root, config));
    out
}

fn dirs_home() -> std::path::PathBuf {
    std::env::var_os("HOME")
        .map(std::path::PathBuf::from)
        .unwrap_or_else(|| std::path::PathBuf::from("/"))
}

#[cfg(test)]
mod tests {
    use super::*;
    use offsend_policy::OffsendProjectConfig;
    use std::fs;
    use std::path::PathBuf;
    use std::process::Command;
    use std::time::{SystemTime, UNIX_EPOCH};

    fn tmp_git_repo() -> PathBuf {
        let nanos = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        let dir = std::env::temp_dir().join(format!("offsend-hook-policy-{nanos}"));
        fs::create_dir_all(&dir).unwrap();
        Command::new("git")
            .args(["init"])
            .current_dir(&dir)
            .output()
            .unwrap();
        dir
    }

    fn enabled_config() -> OffsendProjectConfig {
        OffsendProjectConfig::parse_yaml(
            "version: 1\nhooks:\n  enabled: true\n  git: [pre-commit]\n",
        )
        .unwrap()
    }

    #[test]
    fn git_findings_fail_without_pre_commit() {
        let repo = tmp_git_repo();
        let cfg = enabled_config();
        let git = git_findings(&repo, Some(&cfg));
        assert!(
            git.iter().any(|f| f.id == "git-pre-commit" && f.is_failure),
            "{git:?}"
        );
        assert!(
            git.iter().all(|f| !f.id.ends_with("-hook") || f.id == "git-hook"),
            "CI must not require project AI-editor hooks: {git:?}"
        );
        let _ = fs::remove_dir_all(&repo);
    }

    #[test]
    fn ai_project_findings_are_warn_only() {
        let repo = tmp_git_repo();
        let cfg = enabled_config();
        let ai = ai_project_findings(&repo, Some(&cfg));
        assert!(
            ai.iter().any(|f| f.id == "cursor-hook"),
            "{ai:?}"
        );
        assert!(ai.iter().all(|f| !f.is_failure), "{ai:?}");
        let _ = fs::remove_dir_all(&repo);
    }
}
