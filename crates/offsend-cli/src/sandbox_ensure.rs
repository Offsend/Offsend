//! Ensure sandbox packs for the editor being launched.

use crate::sandbox_launch::{which, EditorTarget};
use crate::sandbox_provider::{EnsureMode, SandboxProvider};
use crate::sandbox_sync;
use std::process::Command;

/// CLI / config override for pack ensure.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum EnsureOverride {
    /// Use provider / pack `ensure`.
    Auto,
    /// Force pull when a pack is configured.
    ForcePull,
    /// Never pull; at most check.
    NoPull,
}

pub fn ensure_for_run(
    provider: &SandboxProvider,
    target: EditorTarget,
    override_mode: EnsureOverride,
) -> Result<(), String> {
    if target == EditorTarget::Cursor {
        return Ok(());
    }
    let editor = target.as_str();
    let Some(_) = provider.pack_for(editor) else {
        return Ok(()); // packless provider / no pack for this editor
    };

    let mode = match override_mode {
        EnsureOverride::Auto => provider.effective_ensure(editor),
        EnsureOverride::ForcePull => EnsureMode::Pull,
        EnsureOverride::NoPull => match provider.effective_ensure(editor) {
            EnsureMode::None => EnsureMode::None,
            _ => EnsureMode::Check,
        },
    };

    match mode {
        EnsureMode::None => Ok(()),
        EnsureMode::Check => check_pack(provider, target),
        EnsureMode::Pull => pull_pack(provider, target),
    }
}

fn check_pack(provider: &SandboxProvider, target: EditorTarget) -> Result<(), String> {
    match sandbox_sync::pack_satisfied(provider, target) {
        Some((_, true, _)) => Ok(()),
        Some((_, false, _)) | None => Err(provider.missing_pack_message(target.as_str())),
    }
}

fn pull_pack(provider: &SandboxProvider, target: EditorTarget) -> Result<(), String> {
    if let Some((_, true, _)) = sandbox_sync::pack_satisfied(provider, target) {
        return Ok(());
    }
    let (program, args) = provider.pack_install_command(target.as_str())?;
    let program_path = which(program.to_str().unwrap_or(provider.binary.as_str())).ok_or_else(
        || {
            format!(
                "Could not find `{}` to install packs.\n{}",
                provider.binary,
                provider.install_hint.trim()
            )
        },
    )?;

    eprintln!(
        "hint: ensuring pack: {} {}",
        program_path.display(),
        args.join(" ")
    );

    let output = Command::new(&program_path)
        .args(&args)
        .output()
        .map_err(|e| format!("pack install failed: {e}"))?;

    if !output.status.success() {
        let code = output.status.code().unwrap_or(-1);
        let stderr = String::from_utf8_lossy(&output.stderr);
        let stdout = String::from_utf8_lossy(&output.stdout);
        let detail = [stderr.trim(), stdout.trim()]
            .into_iter()
            .find(|s| !s.is_empty())
            .unwrap_or("no output");
        return Err(format!(
            "pack install exited {code}: {detail}\n{}",
            provider.missing_pack_message(target.as_str())
        ));
    }

    match sandbox_sync::pack_satisfied(provider, target) {
        Some((_, true, _)) => Ok(()),
        _ => Err(format!(
            "pack install finished but pack is still missing.\n{}",
            provider.missing_pack_message(target.as_str())
        )),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::sandbox_provider::{EnsureMode, PackInstall, PackSpec, SandboxProvider};
    use std::collections::BTreeMap;

    fn provider_with(ensure: EnsureMode) -> SandboxProvider {
        let mut packs = BTreeMap::new();
        packs.insert(
            "claude".into(),
            PackSpec {
                preferred: "nolabs-ai/claude".into(),
                accepted: vec!["nolabs-ai/claude".into()],
                base_profile: "claude-code".into(),
                ensure: None,
            },
        );
        SandboxProvider {
            name: "test".into(),
            binary: "nono".into(),
            profile_directory: ".offsend/nono".into(),
            detect_env: None,
            run_args: vec!["--".into(), "{agent}".into()],
            install_hint: "hint".into(),
            pack_config_subdir: "nono".into(),
            ensure,
            pack_install: Some(PackInstall {
                args: vec!["pull".into(), "{pack}".into()],
            }),
            packs,
        }
    }

    #[test]
    fn cursor_skips() {
        let p = provider_with(EnsureMode::Check);
        assert!(ensure_for_run(&p, EditorTarget::Cursor, EnsureOverride::Auto).is_ok());
    }

    #[test]
    fn packless_skips() {
        let mut p = provider_with(EnsureMode::Check);
        p.packs.clear();
        assert!(ensure_for_run(&p, EditorTarget::Claude, EnsureOverride::Auto).is_ok());
    }

    #[test]
    fn none_skips_missing() {
        let p = provider_with(EnsureMode::None);
        assert!(ensure_for_run(&p, EditorTarget::Claude, EnsureOverride::Auto).is_ok());
    }

    #[test]
    fn check_fails_when_pack_missing() {
        let p = provider_with(EnsureMode::Check);
        // Prefer a pack name that is almost certainly not installed under ~/.config/nono.
        let mut packs = BTreeMap::new();
        packs.insert(
            "claude".into(),
            PackSpec {
                preferred: "offsend-test/missing-pack-corner".into(),
                accepted: vec!["offsend-test/missing-pack-corner".into()],
                base_profile: "missing-profile".into(),
                ensure: None,
            },
        );
        let mut p = p;
        p.packs = packs;
        let err = ensure_for_run(&p, EditorTarget::Claude, EnsureOverride::Auto).unwrap_err();
        assert!(err.contains("not installed"), "{err}");
        assert!(err.contains("offsend-test/missing-pack-corner"), "{err}");
    }

    #[test]
    fn no_pull_downgrades_pull_to_check() {
        let mut p = provider_with(EnsureMode::Pull);
        p.packs.get_mut("claude").unwrap().preferred = "offsend-test/missing-pack-corner".into();
        p.packs.get_mut("claude").unwrap().accepted =
            vec!["offsend-test/missing-pack-corner".into()];
        // Would attempt pull under Auto; NoPull must only check and fail without invoking pull.
        let err = ensure_for_run(&p, EditorTarget::Claude, EnsureOverride::NoPull).unwrap_err();
        assert!(err.contains("not installed"), "{err}");
        assert!(!err.contains("pack install exited"), "{err}");
    }

    #[test]
    fn no_pull_preserves_explicit_none() {
        let p = provider_with(EnsureMode::None);
        assert!(ensure_for_run(&p, EditorTarget::Claude, EnsureOverride::NoPull).is_ok());
    }

    #[test]
    fn force_pull_without_installer_errors() {
        let mut p = provider_with(EnsureMode::Check);
        p.pack_install = None;
        p.packs.get_mut("claude").unwrap().preferred = "offsend-test/missing-pack-corner".into();
        p.packs.get_mut("claude").unwrap().accepted =
            vec!["offsend-test/missing-pack-corner".into()];
        let err = ensure_for_run(&p, EditorTarget::Claude, EnsureOverride::ForcePull).unwrap_err();
        assert!(err.contains("cannot install packs"), "{err}");
    }

    #[test]
    fn editor_without_pack_entry_skips() {
        let mut p = provider_with(EnsureMode::Check);
        p.packs.remove("claude");
        // Only claude was configured; codex has no pack → skip.
        assert!(ensure_for_run(&p, EditorTarget::Codex, EnsureOverride::Auto).is_ok());
    }
}
