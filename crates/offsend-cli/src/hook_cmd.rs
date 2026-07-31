//! `hook install|uninstall|status`

use crate::hook_ai::{self, AiTarget, GateOptions, ALL_TARGETS};
use crate::hook_git::{self, HookState};
use clap::{Args, Subcommand};
use std::path::PathBuf;
use std::process::ExitCode;

#[derive(Debug, Subcommand)]
pub enum HookCmd {
    /// Install Offsend-managed git and AI-editor hooks.
    Install(InstallArgs),
    /// Remove Offsend-managed hooks.
    Uninstall(UninstallArgs),
    /// Show hook installation status.
    Status(StatusArgs),
}

#[derive(Debug, Args)]
pub struct InstallArgs {
    #[arg(long)]
    pub path: Option<String>,

    /// Target: git, cursor, claude, windsurf, codex, or all (default: git + detected AI editors).
    #[arg(long)]
    pub target: Option<String>,

    /// Install a single git hook (`pre-commit` or `post-merge`). Default: all of `hooks.git`.
    #[arg(long = "type")]
    pub r#type: Option<String>,

    #[arg(long = "fail-on", default_value = "block")]
    pub fail_on: String,

    #[arg(long = "hook-policy", default_value = "soft-block")]
    pub hook_policy: String,

    #[arg(long, default_value_t = false)]
    pub policy: bool,

    #[arg(long, default_value_t = false)]
    pub force: bool,

    #[arg(long = "cli-path")]
    pub cli_path: Option<String>,

    /// Skip confirmation (accepted; install is non-interactive).
    #[arg(long, default_value_t = false)]
    pub yes: bool,

    // Gate toggles — on by default; `--no-*-gate` disables. Positive flags are
    // accepted for Swift CLI compatibility (no-ops since default is already on).
    #[arg(long = "read-gate", alias = "with-read-gate", default_value_t = false)]
    pub read_gate: bool,
    #[arg(long = "no-read-gate", default_value_t = false)]
    pub no_read_gate: bool,

    #[arg(long = "write-gate", alias = "with-write-gate", default_value_t = false)]
    pub write_gate: bool,
    #[arg(long = "no-write-gate", default_value_t = false)]
    pub no_write_gate: bool,

    #[arg(long = "shell-gate", alias = "with-shell-gate", default_value_t = false)]
    pub shell_gate: bool,
    #[arg(long = "no-shell-gate", default_value_t = false)]
    pub no_shell_gate: bool,

    #[arg(long = "shell-audit", alias = "with-shell-audit", default_value_t = false)]
    pub shell_audit: bool,
    #[arg(long = "no-shell-audit", default_value_t = false)]
    pub no_shell_audit: bool,

    #[arg(long = "mcp-gate", alias = "with-mcp-gate", default_value_t = false)]
    pub mcp_gate: bool,
    #[arg(long = "no-mcp-gate", default_value_t = false)]
    pub no_mcp_gate: bool,

    #[arg(long = "subagent-gate", alias = "with-subagent-gate", default_value_t = false)]
    pub subagent_gate: bool,
    #[arg(long = "no-subagent-gate", default_value_t = false)]
    pub no_subagent_gate: bool,

    #[arg(
        long = "mcp-response-gate",
        alias = "with-mcp-response-gate",
        default_value_t = false
    )]
    pub mcp_response_gate: bool,
    #[arg(long = "no-mcp-response-gate", default_value_t = false)]
    pub no_mcp_response_gate: bool,
}

#[derive(Debug, Args)]
pub struct UninstallArgs {
    #[arg(long)]
    pub path: Option<String>,

    #[arg(long)]
    pub target: Option<String>,

    #[arg(long, default_value_t = false)]
    pub force: bool,
}

#[derive(Debug, Args)]
pub struct StatusArgs {
    #[arg(long)]
    pub path: Option<String>,

    /// Target: git, cursor, claude, windsurf, codex, or all (default: all).
    #[arg(long)]
    pub target: Option<String>,

    #[arg(long, default_value = "text")]
    pub format: String,
}

pub fn run(cmd: HookCmd) -> Result<ExitCode, String> {
    match cmd {
        HookCmd::Install(args) => install(args),
        HookCmd::Uninstall(args) => uninstall(args),
        HookCmd::Status(args) => status(args),
    }
}

pub fn install_for_sync(
    repo: &std::path::Path,
    config: Option<&offsend_policy::OffsendProjectConfig>,
    no_hooks: bool,
    dry_run: bool,
) -> Result<(), String> {
    if no_hooks || dry_run {
        return Ok(());
    }
    let cli = current_exe()?;
    let (fail_on, include_policy) = git_hook_options(config);
    let kinds = git_kinds_from_config(config)?;
    for kind in kinds {
        // Never force-overwrite during sync — a foreign pre-commit must be
        // preserved (warn + skip) while AI-editor hooks still install.
        match hook_git::install(repo, kind, &cli, &fail_on, include_policy, false) {
            Ok(_) => {}
            Err(hook_git::GitHookError::AlreadyInstalled(path)) => {
                eprintln!(
                    "warning: git hook skipped — foreign hook already present at {path} (use `offsend hook install --target git --force` to replace)"
                );
            }
            Err(e) => eprintln!("warning: git {}: {e}", kind.as_str()),
        }
    }
    let home = dirs_home();
    let gates = GateOptions::default();
    for target in hook_ai::detected_targets(repo, &home) {
        if let Err(e) = hook_ai::install(target, repo, &cli, "soft-block", &gates) {
            eprintln!("warning: {}: {e}", target.as_str());
        }
    }
    Ok(())
}

fn git_hook_options(config: Option<&offsend_policy::OffsendProjectConfig>) -> (String, bool) {
    let hooks = config.and_then(|c| c.hooks.as_ref());
    let fail_on = hooks
        .and_then(|h| h.fail_on.clone())
        .or_else(|| {
            config
                .and_then(|c| c.check.as_ref())
                .and_then(|c| c.fail_on.clone())
        })
        .unwrap_or_else(|| "block".into());
    let include_policy = hooks
        .and_then(|h| h.policy)
        .or_else(|| config.and_then(|c| c.check.as_ref()).and_then(|c| c.policy))
        .unwrap_or(false);
    (fail_on, include_policy)
}

fn git_kinds_from_config(
    config: Option<&offsend_policy::OffsendProjectConfig>,
) -> Result<Vec<hook_git::GitHookKind>, String> {
    let names = config
        .map(|c| c.git_hooks())
        .unwrap_or_else(|| vec!["pre-commit".into()]);
    hook_git::parse_kinds(&names).map_err(|e| e.to_string())
}

fn git_kinds_from_args(
    args: &InstallArgs,
    config: Option<&offsend_policy::OffsendProjectConfig>,
) -> Result<Vec<hook_git::GitHookKind>, String> {
    if let Some(raw) = args.r#type.as_deref() {
        let kind = hook_git::GitHookKind::parse(raw).ok_or_else(|| {
            format!("Unsupported --type {raw:?}. Supported: pre-commit, post-merge.")
        })?;
        return Ok(vec![kind]);
    }
    git_kinds_from_config(config)
}

fn gate_options_from_args(args: &InstallArgs) -> GateOptions {
    GateOptions {
        read_gate: !args.no_read_gate,
        write_gate: !args.no_write_gate,
        shell_gate: !args.no_shell_gate,
        shell_audit: !args.no_shell_audit,
        mcp_gate: !args.no_mcp_gate,
        subagent_gate: !args.no_subagent_gate,
        mcp_response_gate: !args.no_mcp_response_gate,
    }
}

fn any_no_gate(args: &InstallArgs) -> bool {
    args.no_read_gate
        || args.no_write_gate
        || args.no_shell_gate
        || args.no_shell_audit
        || args.no_mcp_gate
        || args.no_subagent_gate
        || args.no_mcp_response_gate
}

fn install(args: InstallArgs) -> Result<ExitCode, String> {
    let _ = args.yes; // accepted; install is non-interactive
    let root = path_arg(args.path.as_deref());
    if !root.is_dir() {
        return Err(format!(
            "Repository path does not exist: {}",
            root.display()
        ));
    }
    let cli = args
        .cli_path
        .clone()
        .unwrap_or_else(|| current_exe().unwrap_or_else(|_| "offsend".into()));
    let config = offsend_policy::OffsendProjectConfig::find_and_load(&root)
        .ok()
        .flatten()
        .map(|(_, c)| c);

    let gates = gate_options_from_args(&args);
    let target = args.target.as_deref().unwrap_or("default");
    match target {
        "git" => {
            if any_no_gate(&args) {
                return Err(
                    "--no-*-gate flags require an AI-editor target (cursor, claude, windsurf, codex, all)."
                        .into(),
                );
            }
            let kinds = git_kinds_from_args(&args, config.as_ref())?;
            if kinds.is_empty() {
                println!("hooks.git is empty — no git hooks to install");
            }
            for kind in kinds {
                let path = hook_git::install(
                    &root,
                    kind,
                    &cli,
                    &args.fail_on,
                    args.policy,
                    args.force,
                )
                .map_err(|e| e.to_string())?;
                println!("installed git {} ({})", kind.as_str(), path.display());
            }
        }
        "cursor" | "claude" | "windsurf" | "codex" => {
            let t = AiTarget::parse(target).unwrap();
            let repo = hook_git::resolve_repo_root(&root).unwrap_or(root);
            let path = hook_ai::install(t, &repo, &cli, &args.hook_policy, &gates)
                .map_err(|e| e.to_string())?;
            println!("installed {} hook ({})", t.as_str(), path.display());
        }
        "all" => {
            let repo = hook_git::resolve_repo_root(&root).unwrap_or(root);
            for t in ALL_TARGETS {
                match hook_ai::install(t, &repo, &cli, &args.hook_policy, &gates) {
                    Ok(path) => println!("installed {} hook ({})", t.as_str(), path.display()),
                    Err(e) => eprintln!("warning: {}: {e}", t.as_str()),
                }
            }
        }
        "default" => {
            match git_kinds_from_args(&args, config.as_ref()) {
                Ok(kinds) => {
                    for kind in kinds {
                        match hook_git::install(
                            &root,
                            kind,
                            &cli,
                            &args.fail_on,
                            args.policy,
                            args.force,
                        ) {
                            Ok(path) => {
                                println!("installed git {} ({})", kind.as_str(), path.display())
                            }
                            Err(e) => eprintln!("warning: git {}: {e}", kind.as_str()),
                        }
                    }
                }
                Err(e) => eprintln!("warning: git hooks: {e}"),
            }
            let home = dirs_home();
            let repo = hook_git::resolve_repo_root(&root).unwrap_or(root);
            let ai_targets = hook_ai::detected_targets(&repo, &home);
            if ai_targets.is_empty() && any_no_gate(&args) {
                return Err(
                    "--no-*-gate flags require an AI-editor target (cursor, claude, windsurf, codex, all)."
                        .into(),
                );
            }
            for t in ai_targets {
                match hook_ai::install(t, &repo, &cli, &args.hook_policy, &gates) {
                    Ok(path) => println!("installed {} hook ({})", t.as_str(), path.display()),
                    Err(e) => eprintln!("warning: {}: {e}", t.as_str()),
                }
            }
        }
        other => {
            return Err(format!(
                "Unknown --target {other}. Expected git, cursor, claude, windsurf, codex, all."
            ))
        }
    }
    Ok(ExitCode::SUCCESS)
}

fn uninstall(args: UninstallArgs) -> Result<ExitCode, String> {
    let root = path_arg(args.path.as_deref());
    let target = args.target.as_deref().unwrap_or("default");
    let config = offsend_policy::OffsendProjectConfig::find_and_load(&root)
        .ok()
        .flatten()
        .map(|(_, c)| c);
    match target {
        "git" => {
            let kinds = git_kinds_from_config(config.as_ref()).unwrap_or_else(|_| {
                hook_git::GitHookKind::all().to_vec()
            });
            let kinds = if kinds.is_empty() {
                hook_git::GitHookKind::all().to_vec()
            } else {
                kinds
            };
            for kind in kinds {
                match hook_git::uninstall(&root, kind, args.force) {
                    Ok(()) => println!("removed git {} hook", kind.as_str()),
                    Err(e) => eprintln!("warning: git {}: {e}", kind.as_str()),
                }
            }
        }
        "cursor" | "claude" | "windsurf" | "codex" => {
            let t = AiTarget::parse(target).unwrap();
            let repo = hook_git::resolve_repo_root(&root).unwrap_or(root);
            if hook_ai::uninstall(t, &repo).map_err(|e| e.to_string())? {
                println!("removed {} managed hooks", t.as_str());
            } else {
                println!("{}: nothing to remove", t.as_str());
            }
        }
        "all" | "default" => {
            for kind in hook_git::GitHookKind::all() {
                let _ = hook_git::uninstall(&root, *kind, args.force);
            }
            let repo = hook_git::resolve_repo_root(&root).unwrap_or(root);
            for t in ALL_TARGETS {
                let _ = hook_ai::uninstall(t, &repo);
            }
            println!("removed managed hooks");
        }
        other => {
            return Err(format!(
                "Unknown --target {other}. Expected git, cursor, claude, windsurf, codex, all."
            ))
        }
    }
    Ok(ExitCode::SUCCESS)
}

fn status(args: StatusArgs) -> Result<ExitCode, String> {
    let root = path_arg(args.path.as_deref());
    // No `--target` means the default overview (git + editors). Explicit
    // `--target all` is AI-only soft: not-installed is OK, broken is not.
    let target = args.target.as_deref().unwrap_or("default");
    let repo = hook_git::resolve_repo_root(&root).unwrap_or_else(|_| root.clone());

    let mut targets: Vec<(String, String, String)> = Vec::new();
    let include_git = matches!(target, "git" | "all" | "default");
    let ai_list: Vec<AiTarget> = match target {
        "all" | "default" => ALL_TARGETS.to_vec(),
        "cursor" | "claude" | "windsurf" | "codex" => {
            vec![AiTarget::parse(target).expect("validated above")]
        }
        "git" => Vec::new(),
        other => {
            return Err(format!(
                "Unknown --target {other}. Expected git, cursor, claude, windsurf, codex, all."
            ))
        }
    };

    if include_git {
        for kind in hook_git::GitHookKind::all() {
            // Keep the primary pre-commit target labeled `git` for status JSON
            // compatibility (`"target":"git"`); other kinds use `git:<name>`.
            let label = if kind.as_str() == "pre-commit" {
                "git".to_string()
            } else {
                format!("git:{}", kind.as_str())
            };
            match hook_git::status(&root, *kind) {
                Ok(s) => {
                    let state = match s.state {
                        HookState::Installed => "installed",
                        HookState::NotInstalled => "not-installed",
                        HookState::Modified => "modified",
                    };
                    targets.push((label, state.into(), s.hook_path.display().to_string()));
                }
                Err(e) => targets.push((label, "error".into(), e.to_string())),
            }
        }
    }

    for t in ai_list {
        let state = if hook_ai::is_installed(t, &repo) {
            "installed"
        } else {
            "not-installed"
        };
        targets.push((
            t.as_str().into(),
            state.into(),
            t.config_path(&repo).display().to_string(),
        ));
    }

    match args.format.as_str() {
        "json" => {
            let arr: Vec<serde_json::Value> = targets
                .iter()
                .map(|(name, state, path)| {
                    serde_json::json!({
                        "target": name,
                        "state": state,
                        "path": path,
                    })
                })
                .collect();
            println!("{}", serde_json::json!({ "targets": arr }));
        }
        "text" => {
            for (name, state, path) in &targets {
                if name == "git" {
                    println!("git pre-commit: {state} ({path})");
                } else {
                    println!("{name}: {state} ({path})");
                }
            }
        }
        other => {
            return Err(format!(
                "Invalid --format value: {other}. Expected text or json."
            ))
        }
    }

    let code = status_exit_code(target, &targets);
    Ok(ExitCode::from(code))
}

/// Exit `3` when hooks are missing/broken per `docs/cli.md` status rules.
fn status_exit_code(target: &str, targets: &[(String, String, String)]) -> u8 {
    let is_bad = |state: &str| matches!(state, "modified" | "error" | "broken");
    match target {
        // Default overview: git pre-commit must be installed; AI broken → 3.
        "default" => {
            let git_missing = targets
                .iter()
                .any(|(name, state, _)| name == "git" && state != "installed");
            let ai_broken = targets
                .iter()
                .any(|(name, state, _)| name != "git" && !name.starts_with("git:") && is_bad(state));
            if git_missing || ai_broken {
                3
            } else {
                0
            }
        }
        // `--target all`: not-installed is OK; broken/modified → 3.
        "all" => {
            if targets.iter().any(|(_, state, _)| is_bad(state)) {
                3
            } else {
                0
            }
        }
        // Single target: not installed or broken → 3.
        _ => {
            if targets
                .iter()
                .any(|(_, state, _)| state != "installed" || is_bad(state))
            {
                3
            } else {
                0
            }
        }
    }
}

fn path_arg(path: Option<&str>) -> PathBuf {
    path.map(PathBuf::from)
        .unwrap_or_else(|| std::env::current_dir().unwrap_or_else(|_| PathBuf::from(".")))
}

fn current_exe() -> Result<String, String> {
    std::env::current_exe()
        .map(|p| p.display().to_string())
        .map_err(|e| e.to_string())
}

fn dirs_home() -> PathBuf {
    std::env::var_os("HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from("/"))
}
