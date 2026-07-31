//! `offsend run` — launch cursor / claude / codex under sandbox from `.offsend.yml`.

use crate::sandbox_ensure::{self, EnsureOverride};
use crate::sandbox_launch::{
    invocation, which, wrapper_available, EditorTarget, LaunchError, SandboxMechanism,
};
use crate::sandbox_provider;
use crate::sandbox_sync::{self, ChangeKind};
use clap::Args;
use offsend_policy::{OffsendProjectConfig, CONFIG_FILENAME};
use std::path::{Path, PathBuf};
use std::process::{Command, ExitCode};

#[derive(Debug, Args)]
#[command(
    about = "Launch an AI editor under the sandbox from .offsend.yml.",
    long_about = "Starts cursor, claude, or codex. When sandbox.enabled is true and the \
configured sandbox provider binary is installed, Claude Code / Codex are wrapped; \
otherwise the bare binary (or Cursor via open) is launched. Provider files are \
sandbox.<name>.yml (shipped / global / project). Does not trust policy — run \
`offsend policy trust` separately after reviewing .offsend.yml."
)]
pub struct RunArgs {
    /// Editor to launch: cursor, claude, or codex.
    pub editor: String,

    /// Repository path. Defaults to the current directory.
    #[arg(long)]
    pub path: Option<String>,

    /// Run sandbox sync for this editor before launch.
    #[arg(long, default_value_t = false)]
    pub sync: bool,

    /// Install missing provider packs for this editor (`pack_install` argv).
    #[arg(long, default_value_t = false)]
    pub ensure_packs: bool,

    /// Never run pack install; at most check (overrides ensure: pull).
    #[arg(long, default_value_t = false)]
    pub no_ensure_packs: bool,

    /// Arguments forwarded to the editor (after `--`).
    #[arg(trailing_var_arg = true, allow_hyphen_values = true)]
    pub agent_arguments: Vec<String>,
}

pub fn run(args: RunArgs) -> Result<ExitCode, String> {
    if args.ensure_packs && args.no_ensure_packs {
        return Err("use only one of --ensure-packs / --no-ensure-packs".into());
    }

    let Some(target) = EditorTarget::parse(&args.editor) else {
        return Err(LaunchError::UnsupportedTarget(args.editor).to_string());
    };

    let directory = args
        .path
        .map(PathBuf::from)
        .unwrap_or_else(|| std::env::current_dir().unwrap_or_else(|_| PathBuf::from(".")));
    let directory = directory.canonicalize().unwrap_or(directory);

    let config = load_config(&directory);
    let trusted = crate::policy_trust::is_trusted(&directory);
    let resolved = sandbox_provider::resolve(config.as_ref(), Some(&directory), trusted)?;
    for warning in &resolved.warnings {
        eprintln!("warning: {warning}");
    }
    let provider_layer = resolved.layer;
    let provider = resolved.provider;
    let sandbox_enabled =
        sandbox_sync::effective_sandbox_enabled(config.as_ref(), trusted);
    if config
        .as_ref()
        .and_then(|c| c.sandbox.as_ref())
        .and_then(|v| v.get("enabled"))
        .and_then(|v| v.as_bool())
        == Some(false)
        && !trusted
        && sandbox_enabled
    {
        eprintln!(
            "warning: sandbox.enabled: false ignored until `offsend policy trust` \
             (keeping sandbox on)"
        );
    }
    let wrapper = wrapper_available(&provider);

    if args.sync {
        sync_sandbox(&directory, config.as_ref(), target)?;
    }

    let ensure_override = if args.ensure_packs {
        EnsureOverride::ForcePull
    } else if args.no_ensure_packs {
        EnsureOverride::NoPull
    } else {
        EnsureOverride::Auto
    };

    if sandbox_enabled && wrapper && target != EditorTarget::Cursor {
        sandbox_ensure::ensure_for_run(&provider, target, ensure_override)?;
    }

    let forwarded: Vec<String> = args
        .agent_arguments
        .into_iter()
        .skip_while(|a| a == "--")
        .collect();

    let open_path =
        (target == EditorTarget::Cursor).then(|| directory.to_string_lossy().into_owned());
    let inv = invocation(
        target,
        sandbox_enabled,
        &provider,
        wrapper,
        &forwarded,
        open_path.as_deref(),
    )
    .map_err(|e| e.to_string())?;

    if inv.uses_wrapper {
        if let Some(relative) = &inv.profile_relative_path {
            let profile = directory.join(relative);
            if !profile.is_file() {
                return Err(
                    LaunchError::MissingWrapperProfile(format!("./{relative}")).to_string()
                );
            }
            // Pack check already handled by ensure_for_run for check/pull;
            // none mode may still proceed without a pack.
        }
    }

    let program_path = which(&inv.program).ok_or_else(|| {
        if inv.uses_wrapper {
            format!(
                "Could not find `{}` on PATH. Install it:\n{}\n\
                 Or unset sandbox.enabled to launch without a wrapper.",
                provider.binary,
                provider.install_hint.trim()
            )
        } else {
            LaunchError::MissingBinary(inv.program.clone()).to_string()
        }
    })?;

    match inv.mechanism {
        Some(SandboxMechanism::Wrapper) => eprintln!(
            "hint: sandbox: {} ({}, {})",
            provider.name,
            SandboxMechanism::Wrapper.as_str(),
            provider_layer.as_str()
        ),
        Some(mechanism) => eprintln!("hint: sandbox: {}", mechanism.as_str()),
        None => eprintln!(
            "hint: sandbox: off (launching without {})",
            provider.name
        ),
    }
    eprintln!("hint: {}", inv.display);

    exec_replacement(&program_path, &inv.arguments, &directory)
}

fn load_config(directory: &Path) -> Option<OffsendProjectConfig> {
    let path = directory.join(CONFIG_FILENAME);
    match OffsendProjectConfig::load_from_path(&path) {
        Ok(cfg) => cfg,
        Err(_) => None,
    }
}

fn sync_sandbox(
    directory: &Path,
    config: Option<&OffsendProjectConfig>,
    target: EditorTarget,
) -> Result<(), String> {
    let report = sandbox_sync::run(directory, config, target);
    if !report.enabled {
        eprintln!("hint: sandbox sync skipped (sandbox.enabled is not true)");
        return Ok(());
    }
    for change in &report.changes {
        if change.kind != ChangeKind::Unchanged {
            eprintln!("ok: {} {}", change.kind.as_str(), change.relative_path);
        }
    }
    for step in &report.manual_steps {
        eprintln!("hint: {step}");
    }
    for error in &report.errors {
        eprintln!("fail: {error}");
    }
    if !report.errors.is_empty() {
        return Err("sandbox sync failed".into());
    }
    Ok(())
}

fn exec_replacement(
    program: &Path,
    arguments: &[String],
    directory: &Path,
) -> Result<ExitCode, String> {
    std::env::set_current_dir(directory)
        .map_err(|e| format!("chdir {}: {e}", directory.display()))?;

    #[cfg(unix)]
    {
        use std::os::unix::process::CommandExt;
        let err = Command::new(program).args(arguments).exec();
        return Err(format!("Failed to exec {}: {err}", program.display()));
    }

    #[cfg(not(unix))]
    {
        let status = Command::new(program)
            .args(arguments)
            .current_dir(directory)
            .status()
            .map_err(|e| format!("Failed to launch {}: {e}", program.display()))?;
        Ok(ExitCode::from(status.code().unwrap_or(1) as u8))
    }
}
