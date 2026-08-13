//! `doctor` — verify local Offsend CLI setup (subset of Swift OffsendDoctor).

use clap::Args;
use offsend_policy::IgnoreSyncService;
use serde::Serialize;
use std::path::PathBuf;
use std::process::{Command, ExitCode};

#[derive(Debug, Args)]
pub struct DoctorArgs {
    #[arg(long, default_value = "text")]
    pub format: String,

    #[arg(long)]
    pub path: Option<String>,

    /// Skip interactive follow-up prompts (accepted for flag compatibility; no-op in Rust CLI).
    #[arg(long = "no-follow", default_value_t = false)]
    pub no_follow: bool,
}

#[derive(Serialize)]
struct CheckOut {
    name: String,
    status: String,
    message: String,
}

#[derive(Serialize)]
struct ReportOut {
    healthy: bool,
    checks: Vec<CheckOut>,
    suggested_actions: Vec<String>,
}

pub fn run(args: DoctorArgs) -> Result<ExitCode, String> {
    let _ = args.no_follow; // flag accepted for CLI parity; Rust has no interactive follow-up

    let root = args
        .path
        .map(PathBuf::from)
        .unwrap_or_else(|| std::env::current_dir().unwrap_or_else(|_| PathBuf::from(".")));

    let mut checks = Vec::new();
    let mut suggestions = Vec::new();

    // CLI executable
    match std::env::current_exe() {
        Ok(p) => checks.push(CheckOut {
            name: "cli".into(),
            status: "ok".into(),
            message: p.display().to_string(),
        }),
        Err(_) => checks.push(CheckOut {
            name: "cli".into(),
            status: "fail".into(),
            message: "could not resolve current executable".into(),
        }),
    }

    // git
    let git_ok = Command::new("git")
        .arg("--version")
        .output()
        .map(|o| o.status.success())
        .unwrap_or(false);
    checks.push(if git_ok {
        CheckOut {
            name: "git".into(),
            status: "ok".into(),
            message: "git available".into(),
        }
    } else {
        CheckOut {
            name: "git".into(),
            status: "fail".into(),
            message: "git not found in PATH".into(),
        }
    });

    // .offsend.yml
    let (config_path, config) = match offsend_policy::OffsendProjectConfig::find_and_load(&root) {
        Ok(Some((path, cfg))) => (Some(path), Some(cfg)),
        Ok(None) => (None, None),
        Err(e) => {
            checks.push(CheckOut {
                name: "config".into(),
                status: "fail".into(),
                message: format!("failed to load .offsend.yml: {e}"),
            });
            (None, None)
        }
    };
    if let Some(path) = &config_path {
        checks.push(CheckOut {
            name: "config".into(),
            status: "ok".into(),
            message: path.display().to_string(),
        });
    } else if config.is_none() && checks.iter().all(|c| c.name != "config") {
        checks.push(CheckOut {
            name: "config".into(),
            status: "ok".into(),
            message: "no .offsend.yml — machine defaults; run `offsend init` to share with the team"
                .into(),
        });
    }

    // Config lint: serde silently ignores unknown keys, so a typo like
    // `fail-on:` disables the setting with no signal — surface it here.
    if let Some(path) = &config_path {
        if let Ok(raw) = std::fs::read_to_string(path) {
            for finding in offsend_policy::lint_unknown_keys(&raw) {
                checks.push(CheckOut {
                    name: "config-lint".into(),
                    status: "warn".into(),
                    message: finding,
                });
            }
        }
    }
    if let Some(cfg) = &config {
        if let Some(ignore) = &cfg.ignore {
            for slug in ignore.unknown_tool_slugs() {
                checks.push(CheckOut {
                    name: "config-lint".into(),
                    status: "warn".into(),
                    message: format!("ignore.tools: unknown tool `{slug}`"),
                });
            }
        }
        if let Some(hooks) = &cfg.hooks {
            for name in hooks.unknown_git_hooks() {
                checks.push(CheckOut {
                    name: "config-lint".into(),
                    status: "warn".into(),
                    message: format!(
                        "hooks.git: unsupported hook `{name}` (supported: pre-commit, post-merge)"
                    ),
                });
            }
        }
    }

    // seal key
    let key_path = dirs_home().join(".offsend/seal.key");
    let env_key = std::env::var_os("OFFSEND_SEAL_KEY").is_some();
    if key_path.is_file() || env_key {
        checks.push(CheckOut {
            name: "seal_key".into(),
            status: "ok".into(),
            message: if env_key {
                "OFFSEND_SEAL_KEY set".into()
            } else {
                key_path.display().to_string()
            },
        });
    } else {
        checks.push(CheckOut {
            name: "seal_key".into(),
            status: "warn".into(),
            message: "no seal key — run `offsend setup`".into(),
        });
        suggestions.push("offsend setup".into());
    }

    // User-level editor hooks (machine setup). Independent of `.offsend.yml`.
    let user_home = dirs_home();
    for t in crate::hook_ai::user_targets() {
        let id = format!("user-{}-hook", t.as_str());
        if crate::hook_ai::is_installed(t, &user_home) {
            checks.push(CheckOut {
                name: id,
                status: "ok".into(),
                message: t.config_path(&user_home).display().to_string(),
            });
        } else {
            checks.push(CheckOut {
                name: id,
                status: "warn".into(),
                message: format!(
                    "no user-level {} hooks — run `offsend setup`",
                    t.as_str()
                ),
            });
            suggestions.push("offsend setup".into());
        }
    }

    let on_secret_block = config
        .as_ref()
        .and_then(|c| c.context.as_ref())
        .and_then(|ctx| ctx.get("read"))
        .and_then(|r| r.get("on_secret"))
        .and_then(|v| v.as_str())
        == Some("block");
    checks.push(CheckOut {
        name: "seal".into(),
        status: "ok".into(),
        message: if on_secret_block {
            "context.read.on_secret: block (YAML opt-out)".into()
        } else {
            "reads and MCP responses seal secrets (machine default)".into()
        },
    });

    // git hooks
    let hooks_on = crate::hook_policy::hooks_required(config.as_ref());
    if hooks_on {
        for finding in crate::hook_policy::findings(&root, config.as_ref()) {
            let status = if finding.is_failure { "fail" } else { "warn" };
            checks.push(CheckOut {
                name: finding.id.clone(),
                status: status.into(),
                message: finding.message.clone(),
            });
            if finding.id.starts_with("git-") || finding.id == "git-hook" {
                suggestions.push("offsend sync".into());
            } else if finding.id.ends_with("-hook") {
                suggestions.push("offsend setup".into());
            }
        }
    } else if config
        .as_ref()
        .is_some_and(|c| !c.hooks_enabled())
    {
        checks.push(CheckOut {
            name: "hooks".into(),
            status: "ok".into(),
            message: "hooks.enabled is false — skipped".into(),
        });
    }

    let repo = crate::hook_git::resolve_repo_root(&root).unwrap_or(root.clone());
    let home = dirs_home();

    // policy-trust
    match crate::policy_trust::status(&repo) {
        crate::policy_trust::TrustStatus::Trusted => checks.push(CheckOut {
            name: "policy-trust".into(),
            status: "ok".into(),
            message: "workspace .offsend.yml matches trusted snapshot".into(),
        }),
        crate::policy_trust::TrustStatus::Missing => {
            if config_path.is_some() {
                checks.push(CheckOut {
                    name: "policy-trust".into(),
                    status: "warn".into(),
                    message: "no trusted policy snapshot — run `offsend policy trust`".into(),
                });
                suggestions.push("offsend policy trust".into());
            }
        }
        crate::policy_trust::TrustStatus::Drift(reason) => {
            checks.push(CheckOut {
                name: "policy-trust".into(),
                status: "warn".into(),
                message: reason,
            });
            suggestions.push("offsend policy trust".into());
        }
        crate::policy_trust::TrustStatus::Invalid(reason) => checks.push(CheckOut {
            name: "policy-trust".into(),
            status: "warn".into(),
            message: reason,
        }),
    }

    // ignore-sync / rules drift
    if config_path.is_some() {
        let sync = IgnoreSyncService::run(&repo, true);
        if sync.has_errors() {
            checks.push(CheckOut {
                name: "ignore-sync".into(),
                status: "warn".into(),
                message: sync
                    .errors
                    .first()
                    .cloned()
                    .unwrap_or_else(|| "ignore sync dry-run failed".into()),
            });
        } else {
            let would_change = !sync.created_relative_paths.is_empty()
                || !sync.updated_relative_paths.is_empty()
                || sync.gitignore_updated
                || sync.exclude_updated;
            if would_change {
                let mut parts = Vec::new();
                if !sync.created_relative_paths.is_empty() {
                    parts.push(format!("create {}", sync.created_relative_paths.len()));
                }
                if !sync.updated_relative_paths.is_empty() {
                    parts.push(format!("update {}", sync.updated_relative_paths.len()));
                }
                checks.push(CheckOut {
                    name: "ignore-sync".into(),
                    status: "warn".into(),
                    message: format!(
                        "materialized ignore/rule files are behind .offsend.yml ({})",
                        parts.join(", ")
                    ),
                });
                suggestions.push("offsend sync".into());
            } else {
                checks.push(CheckOut {
                    name: "ignore-sync".into(),
                    status: "ok".into(),
                    message: "ignore files match .offsend.yml".into(),
                });
            }
        }
    }

    // Confirm installed hooks when policy is enabled (failures already reported above).
    if hooks_on {
        let targets = crate::hook_ai::detected_targets(&repo, &home);
        for t in targets {
            if crate::hook_ai::is_installed(t, &repo)
                && !checks
                    .iter()
                    .any(|c| c.name == format!("{}-hook", t.as_str()))
            {
                checks.push(CheckOut {
                    name: format!("{}-hook", t.as_str()),
                    status: "ok".into(),
                    message: t.config_path(&repo).display().to_string(),
                });
            }
        }
        for kind in crate::hook_git::GitHookKind::all() {
            let id = format!("git-{}", kind.as_str());
            if checks.iter().any(|c| c.name == id) {
                continue;
            }
            if let Ok(s) = crate::hook_git::status(&root, *kind) {
                if matches!(s.state, crate::hook_git::HookState::Installed) {
                    checks.push(CheckOut {
                        name: id,
                        status: "ok".into(),
                        message: s.hook_path.display().to_string(),
                    });
                }
            }
        }
    }

    let trusted = crate::policy_trust::is_trusted(&root);
    if crate::sandbox_sync::effective_sandbox_enabled(config.as_ref(), trusted) {
        match crate::sandbox_provider::resolve(config.as_ref(), Some(&root), trusted) {
            Ok(resolved) => {
                let provider = &resolved.provider;
                let wrapper = crate::sandbox_launch::wrapper_available(provider);
                let source = resolved
                    .source_path
                    .as_ref()
                    .map(|p| p.display().to_string())
                    .unwrap_or_else(|| format!("shipped sandbox.{}.yml", resolved.id));
                checks.push(CheckOut {
                    name: "sandbox-provider".into(),
                    status: "ok".into(),
                    message: format!(
                        "id={}, binary={}, layer={}, source={}, ensure={}",
                        resolved.id,
                        provider.binary,
                        resolved.layer.as_str(),
                        source,
                        provider.ensure.as_str()
                    ),
                });
                for warning in &resolved.warnings {
                    checks.push(CheckOut {
                        name: "sandbox-provider".into(),
                        status: "warn".into(),
                        message: warning.clone(),
                    });
                }
                checks.push(CheckOut {
                    name: "sandbox-mechanism".into(),
                    status: "ok".into(),
                    message: format!(
                        "cursor={}, claude={}, codex={}",
                        crate::sandbox_launch::plan(
                            crate::sandbox_launch::EditorTarget::Cursor,
                            wrapper
                        )
                        .as_str(),
                        crate::sandbox_launch::plan(
                            crate::sandbox_launch::EditorTarget::Claude,
                            wrapper
                        )
                        .as_str(),
                        crate::sandbox_launch::plan(
                            crate::sandbox_launch::EditorTarget::Codex,
                            wrapper
                        )
                        .as_str()
                    ),
                });
                if !wrapper {
                    suggestions.push(format!(
                        "Install sandbox wrapper `{}` for Claude/Codex:\n{}",
                        provider.binary,
                        provider.install_hint.trim()
                    ));
                }
            }
            Err(e) => {
                checks.push(CheckOut {
                    name: "sandbox-provider".into(),
                    status: "fail".into(),
                    message: e,
                });
            }
        }
        for finding in crate::sandbox_policy::findings(&root, config.as_ref()) {
            checks.push(CheckOut {
                name: "sandbox-policy".into(),
                status: if finding.is_failure { "fail" } else { "warn" }.into(),
                message: finding.message,
            });
        }
    }

    // Deduplicate suggestions while preserving order.
    let mut seen = std::collections::HashSet::new();
    suggestions.retain(|s| seen.insert(s.clone()));

    let healthy = !checks.iter().any(|c| c.status == "fail");
    let report = ReportOut {
        healthy,
        checks,
        suggested_actions: suggestions,
    };

    match args.format.as_str() {
        "json" => {
            println!(
                "{}",
                serde_json::to_string_pretty(&report).map_err(|e| e.to_string())?
            );
        }
        "text" => {
            for c in &report.checks {
                println!("[{}] {}: {}", c.status, c.name, c.message);
            }
            if !report.suggested_actions.is_empty() {
                println!("suggestions:");
                for s in &report.suggested_actions {
                    println!("  - {s}");
                }
            }
            println!(
                "{}",
                if report.healthy {
                    "healthy"
                } else {
                    "unhealthy"
                }
            );
        }
        other => return Err(format!("Invalid --format value: {other}")),
    }

    Ok(if healthy {
        ExitCode::SUCCESS
    } else {
        ExitCode::from(2)
    })
}

fn dirs_home() -> PathBuf {
    std::env::var_os("HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from("/"))
}
