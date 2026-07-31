//! Verify that declared `hooks.enabled` matches installed git / AI-editor hooks.

use crate::hook_ai::{self, AiTarget};
use crate::hook_git::{self, HookState};
use offsend_policy::OffsendProjectConfig;
use std::path::Path;

pub struct Finding {
    pub id: String,
    pub message: String,
    pub is_failure: bool,
}

/// Whether `doctor` / `check --policy` should require hooks.
/// No `.offsend.yml` → do not enforce (nothing declared).
pub fn hooks_required(config: Option<&OffsendProjectConfig>) -> bool {
    config.map(OffsendProjectConfig::hooks_enabled).unwrap_or(false)
}

/// Whether `sync` should install hooks.
/// No `.offsend.yml` → install (preserve previous behavior); explicit `false` skips.
pub fn should_install(config: Option<&OffsendProjectConfig>) -> bool {
    config.map(OffsendProjectConfig::hooks_enabled).unwrap_or(true)
}

pub fn findings(root: &Path, config: Option<&OffsendProjectConfig>) -> Vec<Finding> {
    if !hooks_required(config) {
        return Vec::new();
    }

    let mut findings = Vec::new();
    let repo = hook_git::resolve_repo_root(root).unwrap_or_else(|_| root.to_path_buf());
    let home = dirs_home();

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

    for target in hook_ai::detected_targets(&repo, &home) {
        if !hook_ai::is_installed(target, &repo) {
            findings.push(ai_missing(target));
        }
    }

    // Config files present without the managed marker are also a policy failure —
    // someone expected hooks here but sync/install did not complete.
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
                    "hooks.enabled is true but {} exists without Offsend managed marker. Run: offsend hook install --target {}",
                    path.display(),
                    target.as_str()
                ),
                is_failure: true,
            });
        }
    }

    findings
}

fn ai_missing(target: AiTarget) -> Finding {
    Finding {
        id: format!("{}-hook", target.as_str()),
        message: format!(
            "hooks.enabled is true but {} hooks are not installed. Run: offsend sync",
            target.as_str()
        ),
        is_failure: true,
    }
}

fn dirs_home() -> std::path::PathBuf {
    std::env::var_os("HOME")
        .map(std::path::PathBuf::from)
        .unwrap_or_else(|| std::path::PathBuf::from("/"))
}
