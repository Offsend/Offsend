//! Verify that generated sandbox configuration still enforces the declared policy.

use crate::sandbox_launch::{plan, EditorTarget, SandboxMechanism};
use crate::sandbox_sync::{self, ChangeKind};
use offsend_policy::OffsendProjectConfig;
use serde_json::Value;
use std::fs;
use std::path::{Path, PathBuf};

pub struct Finding {
    pub message: String,
    pub is_failure: bool,
}

pub fn findings(root: &Path, config: Option<&OffsendProjectConfig>) -> Vec<Finding> {
    let trusted = crate::policy_trust::is_trusted(root);
    if !sandbox_sync::effective_sandbox_enabled(config, trusted) {
        return Vec::new();
    }

    let provider = match crate::sandbox_provider::resolve_provider(config, Some(root), trusted)
    {
        Ok(p) => p,
        Err(e) => {
            return vec![Finding {
                message: e,
                is_failure: true,
            }];
        }
    };
    let wrapper = crate::sandbox_launch::wrapper_available(&provider);
    let targets = sandbox_sync::default_targets();
    let mut findings = Vec::new();
    let drift = sandbox_sync::run_targets(root, config, &targets, true);
    for change in drift
        .changes
        .iter()
        .filter(|change| matches!(change.kind, ChangeKind::Created | ChangeKind::Updated))
    {
        findings.push(Finding {
            message: format!(
                "Sandbox config drift in {}: policy in .offsend.yml is ahead of this file. Run: offsend sync",
                change.relative_path
            ),
            is_failure: true,
        });
    }

    for target in targets {
        match plan(target, wrapper) {
            SandboxMechanism::CursorNative => cursor_findings(root, &mut findings),
            SandboxMechanism::ClaudeNative => claude_findings(root, true, &mut findings),
            SandboxMechanism::Wrapper => {
                if target == EditorTarget::Claude {
                    claude_findings(root, false, &mut findings);
                }
                if let Some((_, ok, _)) = sandbox_sync::pack_satisfied(&provider, target) {
                    if !ok {
                        // Profile is written by sync; the pack is a host install
                        // step. Warn so CI/`check --policy` can pass after sync
                        // without requiring every pack on the machine.
                        findings.push(Finding {
                            message: provider.missing_pack_message(target.as_str()),
                            is_failure: false,
                        });
                    }
                }
            }
            SandboxMechanism::CodexUserScope => codex_findings(&mut findings),
            SandboxMechanism::Unavailable => findings.push(Finding {
                message: format!(
                    "{} has no sandbox, so sandbox.enabled cannot be honored there. Nothing is enforced for that editor.",
                    target.as_str()
                ),
                is_failure: false,
            }),
        }
    }
    findings
}

fn cursor_findings(root: &Path, findings: &mut Vec<Finding>) {
    let path = ".cursor/sandbox.json";
    let Some(object) = load_json_object(&root.join(path)) else {
        return;
    };
    if object.get("type").and_then(Value::as_str) == Some("insecure_none") {
        findings.push(Finding {
            message: format!("{path}: type is insecure_none, which disables the sandbox entirely while .offsend.yml requires one."),
            is_failure: true,
        });
    }
}

fn claude_findings(root: &Path, owns_filesystem: bool, findings: &mut Vec<Finding>) {
    let path = ".claude/settings.json";
    let Some(object) = load_json_object(&root.join(path)) else {
        return;
    };
    let Some(sandbox) = object.get("sandbox").and_then(Value::as_object) else {
        return;
    };
    if !owns_filesystem {
        return;
    }
    if sandbox.get("enabled").and_then(Value::as_bool) != Some(true) {
        findings.push(Finding {
            message: format!(
                "{path}: sandbox.enabled is not true while .offsend.yml requires a sandbox."
            ),
            is_failure: true,
        });
    }
    if sandbox
        .get("allowUnsandboxedCommands")
        .and_then(Value::as_bool)
        == Some(true)
    {
        findings.push(Finding {
            message: format!("{path}: allowUnsandboxedCommands is true, so any command that fails inside the sandbox can be retried outside it. The sandbox then guarantees nothing."),
            is_failure: true,
        });
    }
    if sandbox
        .get("filesystem")
        .and_then(Value::as_object)
        .and_then(|filesystem| filesystem.get("disabled"))
        .and_then(Value::as_bool)
        == Some(true)
    {
        findings.push(Finding {
            message: format!("{path}: filesystem.disabled is true, which drops every read restriction while leaving the sandbox nominally enabled."),
            is_failure: true,
        });
    }
}

fn codex_findings(findings: &mut Vec<Finding>) {
    let path = home().join(".codex/config.toml");
    let Ok(text) = fs::read_to_string(&path) else {
        findings.push(Finding {
            message: "Codex sandboxing is configured in ~/.codex/config.toml, outside this repository. Offsend cannot verify it; set sandbox_mode there yourself.".into(),
            is_failure: false,
        });
        return;
    };
    if text.lines().any(|line| {
        let line = line.trim();
        line.starts_with("sandbox_mode")
            && (line.contains("\"danger-full-access\"") || line.contains("'danger-full-access'"))
    }) {
        findings.push(Finding {
            message: "~/.codex/config.toml: sandbox_mode = \"danger-full-access\" removes the sandbox while .offsend.yml requires one.".into(),
            is_failure: true,
        });
    }
}

fn load_json_object(path: &Path) -> Option<serde_json::Map<String, Value>> {
    fs::read_to_string(path)
        .ok()
        .and_then(|text| serde_json::from_str::<Value>(&text).ok())
        .and_then(|value| value.as_object().cloned())
}

fn home() -> PathBuf {
    std::env::var_os("HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from("/"))
}
