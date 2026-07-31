//! Materialize sandbox config for one editor — subset of Swift `SandboxSyncService`
//! used by `offsend run --sync`.

use crate::sandbox_launch::{launch_hint, plan, wrapper_available, EditorTarget, SandboxMechanism};
use crate::sandbox_provider::{self, PackSpec, SandboxProvider};
use offsend_policy::OffsendProjectConfig;
use serde_json::{json, Map, Value};
use std::fs;
use std::path::{Path, PathBuf};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum NetworkDefault {
    Deny,
    Allow,
}

impl NetworkDefault {
    fn effective(raw: Option<&str>) -> Self {
        match raw {
            Some("allow") => Self::Allow,
            _ => Self::Deny,
        }
    }

    fn as_str(self) -> &'static str {
        match self {
            Self::Deny => "deny",
            Self::Allow => "allow",
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct FileChange {
    pub relative_path: String,
    pub kind: ChangeKind,
    pub mechanism: SandboxMechanism,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ChangeKind {
    Created,
    Updated,
    Unchanged,
}

impl ChangeKind {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Created => "created",
            Self::Updated => "updated",
            Self::Unchanged => "unchanged",
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SyncReport {
    pub enabled: bool,
    pub changes: Vec<FileChange>,
    pub uncovered_patterns: Vec<String>,
    pub manual_steps: Vec<String>,
    pub errors: Vec<String>,
}

pub fn pack_satisfied<'a>(
    provider: &'a SandboxProvider,
    target: EditorTarget,
) -> Option<(&'a PackSpec, bool, String)> {
    let req = provider.pack_for(target.as_str())?;
    let (ok, detail) = probe_pack(provider, req);
    Some((req, ok, detail))
}

fn pack_config_home(subdir: &str) -> PathBuf {
    let base = if let Ok(xdg) = std::env::var("XDG_CONFIG_HOME") {
        if !xdg.is_empty() {
            PathBuf::from(xdg)
        } else {
            dirs_home().join(".config")
        }
    } else {
        dirs_home().join(".config")
    };
    base.join(subdir)
}

fn dirs_home() -> PathBuf {
    std::env::var_os("HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from("/"))
}

fn probe_pack(provider: &SandboxProvider, req: &PackSpec) -> (bool, String) {
    let root = pack_config_home(&provider.pack_config_subdir);
    let accepted = req.accepted_or_preferred();
    for pack in &accepted {
        let mut parts = pack.splitn(2, '/');
        let Some(ns) = parts.next() else { continue };
        let Some(name) = parts.next() else { continue };
        let dir = root.join("packages").join(ns).join(name);
        if dir.is_dir() {
            return (true, (*pack).to_string());
        }
    }
    for lock_name in [
        "packages-lock.json",
        "lockfile.json",
        "packages/lockfile.json",
    ] {
        let lock = root.join(lock_name);
        if let Ok(text) = fs::read_to_string(&lock) {
            if let Ok(Value::Object(obj)) = serde_json::from_str::<Value>(&text) {
                if let Some(Value::Object(packages)) = obj.get("packages") {
                    for pack in &accepted {
                        if packages.contains_key(*pack) {
                            return (true, (*pack).to_string());
                        }
                    }
                }
            }
        }
    }
    let profiles = root.join("profiles");
    for name in [
        format!("{}.json", req.base_profile),
        format!("{}.profile.json", req.base_profile),
    ] {
        if profiles.join(&name).is_file() {
            return (true, req.base_profile.clone());
        }
    }
    (false, String::new())
}

/// Raw `sandbox.enabled == true` (ignores trust). Prefer [`effective_sandbox_enabled`].
#[allow(dead_code)]
pub fn sandbox_enabled(config: Option<&OffsendProjectConfig>) -> bool {
    config
        .and_then(|c| c.sandbox.as_ref())
        .and_then(|v| v.get("enabled"))
        .and_then(|v| v.as_bool())
        == Some(true)
}

/// `enabled: true` always applies. `enabled: false` is ignored until policy is trusted
/// (agent cannot turn the sandbox off by editing `.offsend.yml` alone).
pub fn effective_sandbox_enabled(config: Option<&OffsendProjectConfig>, trusted: bool) -> bool {
    let declared = config
        .and_then(|c| c.sandbox.as_ref())
        .and_then(|v| v.get("enabled"))
        .and_then(|v| v.as_bool());
    match declared {
        Some(true) => true,
        // Loosening: honor false only after trust; otherwise keep sandbox on.
        Some(false) => !trusted,
        None => false,
    }
}

/// Returns `(egress_is_deny, allow_domains)` after applying trust rules.
#[cfg(test)]
pub(crate) fn network_policy_for_test(
    config: Option<&OffsendProjectConfig>,
    trusted: bool,
) -> (bool, Vec<String>) {
    let (default, allow) = network_settings(config, trusted);
    (default == NetworkDefault::Deny, allow)
}

fn network_settings(
    config: Option<&OffsendProjectConfig>,
    trusted: bool,
) -> (NetworkDefault, Vec<String>) {
    let sandbox = config.and_then(|c| c.sandbox.as_ref());
    let network = sandbox.and_then(|s| s.get("network"));
    let mut default = NetworkDefault::effective(
        network
            .and_then(|n| n.get("default"))
            .and_then(|v| v.as_str()),
    );
    let mut allow = network
        .and_then(|n| n.get("allow"))
        .and_then(|v| v.as_sequence())
        .map(|seq| {
            seq.iter()
                .filter_map(|v| v.as_str())
                .map(str::trim)
                .filter(|s| !s.is_empty())
                .map(str::to_string)
                .collect::<Vec<_>>()
        })
        .unwrap_or_default();
    // Loosening egress requires trust.
    if !trusted {
        if default == NetworkDefault::Allow {
            default = NetworkDefault::Deny;
        }
        allow.clear();
    }
    allow.sort();
    (default, allow)
}

fn path_coverage(patterns: &[String]) -> (Vec<String>, Vec<String>) {
    let mut expressible = Vec::new();
    let mut uncovered = Vec::new();
    for pattern in patterns {
        let trimmed = pattern.trim();
        if trimmed.is_empty() {
            continue;
        }
        if trimmed
            .chars()
            .any(|c| matches!(c, '*' | '?' | '[' | ']' | '!'))
        {
            uncovered.push(trimmed.to_string());
        } else {
            expressible.push(trimmed.to_string());
        }
    }
    (expressible, uncovered)
}

pub fn run(
    root: &Path,
    config: Option<&OffsendProjectConfig>,
    target: EditorTarget,
) -> SyncReport {
    run_targets(root, config, &[target], false)
}

pub fn default_targets() -> [EditorTarget; 3] {
    [
        EditorTarget::Cursor,
        EditorTarget::Claude,
        EditorTarget::Codex,
    ]
}

pub fn run_targets(
    root: &Path,
    config: Option<&OffsendProjectConfig>,
    targets: &[EditorTarget],
    dry_run: bool,
) -> SyncReport {
    let trusted = crate::policy_trust::is_trusted(root);
    if !effective_sandbox_enabled(config, trusted) {
        return SyncReport {
            enabled: false,
            changes: vec![],
            uncovered_patterns: vec![],
            manual_steps: vec![],
            errors: vec![],
        };
    }

    let (egress, allowed_domains) = network_settings(config, trusted);
    let patterns = config
        .and_then(|c| c.ignore.as_ref())
        .map(|i| i.patterns_or_empty().to_vec())
        .unwrap_or_default();
    let (deny_read, uncovered) = path_coverage(&patterns);
    let provider = match sandbox_provider::resolve_provider(config, Some(root), trusted) {
        Ok(p) => p,
        Err(e) => {
            return SyncReport {
                enabled: true,
                changes: vec![],
                uncovered_patterns: uncovered,
                manual_steps: vec![],
                errors: vec![e],
            };
        }
    };
    let wrapper = wrapper_available(&provider);
    let mut changes = Vec::new();
    let mut manual_steps = Vec::new();
    let mut errors = Vec::new();

    for target in targets.iter().copied() {
        match plan(target, wrapper) {
            SandboxMechanism::CursorNative => {
                match write_cursor_sandbox(
                    root,
                    egress,
                    &allowed_domains,
                    dry_run,
                    SandboxMechanism::CursorNative,
                ) {
                    Ok(c) => changes.push(c),
                    Err(e) => errors.push(e),
                }
            }
            SandboxMechanism::ClaudeNative => {
                match write_claude_sandbox(
                    root,
                    egress,
                    &allowed_domains,
                    &deny_read,
                    true,
                    dry_run,
                    SandboxMechanism::ClaudeNative,
                ) {
                    Ok(c) => changes.push(c),
                    Err(e) => errors.push(e),
                }
            }
            SandboxMechanism::Wrapper => {
                match write_wrapper_profile(
                    root,
                    &provider,
                    target,
                    egress,
                    &allowed_domains,
                    &deny_read,
                    dry_run,
                    SandboxMechanism::Wrapper,
                ) {
                    Ok(c) => changes.push(c),
                    Err(e) => errors.push(e),
                }
                if target == EditorTarget::Claude {
                    match write_claude_sandbox(
                        root,
                        egress,
                        &allowed_domains,
                        &deny_read,
                        false,
                        dry_run,
                        SandboxMechanism::Wrapper,
                    ) {
                        Ok(c) => changes.push(c),
                        Err(e) => errors.push(e),
                    }
                }
                if let Some((_, ok, _)) = pack_satisfied(&provider, target) {
                    if !ok {
                        manual_steps.push(provider.missing_pack_message(target.as_str()));
                    }
                }
                manual_steps.push(launch_hint(&provider, target));
            }
            SandboxMechanism::CodexUserScope => {
                manual_steps.push(
                    "Codex sandboxing lives in ~/.codex/config.toml, outside this repository. \
                     Set sandbox_mode = \"workspace-write\" and the network policy there yourself; \
                     Offsend does not write user-scope files."
                        .into(),
                );
            }
            SandboxMechanism::Unavailable => {}
        }
    }

    SyncReport {
        enabled: true,
        changes,
        uncovered_patterns: uncovered,
        manual_steps,
        errors,
    }
}

fn write_cursor_sandbox(
    root: &Path,
    egress: NetworkDefault,
    allowed_domains: &[String],
    dry_run: bool,
    mechanism: SandboxMechanism,
) -> Result<FileChange, String> {
    let relative = ".cursor/sandbox.json";
    let path = root.join(relative);
    let mut object = load_json_object(&path)?;
    let ty = object.get("type").and_then(|v| v.as_str()).unwrap_or("");
    if ty != "workspace_readonly" {
        object.insert("type".into(), Value::String("workspace_readwrite".into()));
    }
    let mut network = object
        .get("networkPolicy")
        .and_then(|v| v.as_object())
        .cloned()
        .unwrap_or_default();
    network.insert("default".into(), Value::String(egress.as_str().into()));
    network.insert(
        "allow".into(),
        Value::Array(allowed_domains.iter().cloned().map(Value::String).collect()),
    );
    object.insert("networkPolicy".into(), Value::Object(network));
    write_json(
        root,
        relative,
        &path,
        &Value::Object(object),
        dry_run,
        mechanism,
    )
}

fn write_claude_sandbox(
    root: &Path,
    egress: NetworkDefault,
    allowed_domains: &[String],
    deny_read: &[String],
    owns_filesystem: bool,
    dry_run: bool,
    mechanism: SandboxMechanism,
) -> Result<FileChange, String> {
    let relative = ".claude/settings.json";
    let path = root.join(relative);
    let mut object = load_json_object(&path)?;
    let mut sandbox = object
        .get("sandbox")
        .and_then(|v| v.as_object())
        .cloned()
        .unwrap_or_default();
    sandbox.insert("enabled".into(), Value::Bool(owns_filesystem));
    if owns_filesystem {
        sandbox.insert("allowUnsandboxedCommands".into(), Value::Bool(false));
        let mut network = sandbox
            .get("network")
            .and_then(|v| v.as_object())
            .cloned()
            .unwrap_or_default();
        match egress {
            NetworkDefault::Deny => {
                network.insert(
                    "allowedDomains".into(),
                    Value::Array(allowed_domains.iter().cloned().map(Value::String).collect()),
                );
            }
            NetworkDefault::Allow => {
                network.remove("allowedDomains");
            }
        }
        sandbox.insert("network".into(), Value::Object(network));
        let mut filesystem = sandbox
            .get("filesystem")
            .and_then(|v| v.as_object())
            .cloned()
            .unwrap_or_default();
        filesystem.remove("disabled");
        filesystem.insert(
            "denyRead".into(),
            Value::Array(deny_read.iter().cloned().map(Value::String).collect()),
        );
        sandbox.insert("filesystem".into(), Value::Object(filesystem));
    }
    object.insert("sandbox".into(), Value::Object(sandbox));
    write_json(
        root,
        relative,
        &path,
        &Value::Object(object),
        dry_run,
        mechanism,
    )
}

fn write_wrapper_profile(
    root: &Path,
    provider: &SandboxProvider,
    target: EditorTarget,
    egress: NetworkDefault,
    allowed_domains: &[String],
    deny_read: &[String],
    dry_run: bool,
    mechanism: SandboxMechanism,
) -> Result<FileChange, String> {
    let relative = provider.profile_relative_path(target.as_str());
    let path = root.join(&relative);
    let network = match egress {
        NetworkDefault::Deny if allowed_domains.is_empty() => json!({ "block": true }),
        NetworkDefault::Deny => json!({ "allow_domain": allowed_domains }),
        NetworkDefault::Allow => json!({ "block": false }),
    };
    let base_profile = provider
        .pack_for(target.as_str())
        .map(|p| p.base_profile.as_str())
        .unwrap_or("default");
    let object = json!({
        "extends": base_profile,
        "meta": {
            "name": format!("offsend-{}", target.as_str()),
            "description": "Generated by offsend sync from .offsend.yml",
        },
        "workdir": { "access": "readwrite" },
        "policy": { "add_deny_access": deny_read },
        "network": network,
    });
    write_json(root, &relative, &path, &object, dry_run, mechanism)
}

fn load_json_object(path: &Path) -> Result<Map<String, Value>, String> {
    if !path.exists() {
        return Ok(Map::new());
    }
    let text = fs::read_to_string(path).map_err(|e| format!("{}: {e}", path.display()))?;
    let value: Value =
        serde_json::from_str(&text).map_err(|e| format!("{}: {e}", path.display()))?;
    match value {
        Value::Object(map) => Ok(map),
        _ => Err(format!("{}: expected JSON object", path.display())),
    }
}

fn write_json(
    root: &Path,
    relative: &str,
    path: &Path,
    value: &Value,
    dry_run: bool,
    mechanism: SandboxMechanism,
) -> Result<FileChange, String> {
    let mut data = serde_json::to_vec_pretty(value).map_err(|e| e.to_string())?;
    if !data.ends_with(b"\n") {
        data.push(b'\n');
    }
    // Compare against the exact bytes we would write (including trailing newline).
    let existing = fs::read(path).ok();
    if existing.as_ref() == Some(&data) {
        return Ok(FileChange {
            relative_path: relative.to_string(),
            kind: ChangeKind::Unchanged,
            mechanism,
        });
    }
    let kind = if existing.is_none() {
        ChangeKind::Created
    } else {
        ChangeKind::Updated
    };
    if dry_run {
        return Ok(FileChange {
            relative_path: relative.to_string(),
            kind,
            mechanism,
        });
    }
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent).map_err(|e| format!("{}: {e}", parent.display()))?;
    }
    fs::write(path, &data).map_err(|e| format!("{}: {e}", path.display()))?;
    let _ = root;
    Ok(FileChange {
        relative_path: relative.to_string(),
        kind,
        mechanism,
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::time::{SystemTime, UNIX_EPOCH};

    fn temp_workdir(label: &str) -> PathBuf {
        let nanos = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        let dir = std::env::temp_dir().join(format!("offsend-run-{label}-{nanos}"));
        fs::create_dir_all(&dir).unwrap();
        dir
    }

    #[test]
    fn sync_skipped_when_disabled() {
        let dir = temp_workdir("skip");
        let report = run(&dir, None, EditorTarget::Claude);
        assert!(!report.enabled);
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn writes_wrapper_profile_when_enabled() {
        let dir = temp_workdir("nono");
        // Shipped nono treats NONO_CAP_FILE as wrapper-available (no PATH dependency).
        std::env::set_var("NONO_CAP_FILE", "1");
        let yaml = r#"
version: 1
sandbox:
  enabled: true
  provider: nono
ignore:
  patterns:
    - secrets
    - "*.pem"
"#;
        let cfg = OffsendProjectConfig::parse_yaml(yaml).unwrap();
        let report = run(&dir, Some(&cfg), EditorTarget::Claude);
        assert!(report.enabled);
        assert!(report
            .changes
            .iter()
            .any(|c| c.relative_path.contains("offsend-claude.json")));
        assert!(report.uncovered_patterns.contains(&"*.pem".to_string()));
        let path = dir.join(".offsend/nono/offsend-claude.json");
        assert!(path.is_file());
        std::env::remove_var("NONO_CAP_FILE");
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn untrusted_enabled_false_still_syncs() {
        let dir = temp_workdir("force-on");
        std::env::set_var("NONO_CAP_FILE", "1");
        let yaml = r#"
version: 1
sandbox:
  enabled: false
  provider: nono
"#;
        let cfg = OffsendProjectConfig::parse_yaml(yaml).unwrap();
        // No trust snapshot in temp dir → false is ignored → sandbox stays on.
        let report = run(&dir, Some(&cfg), EditorTarget::Claude);
        assert!(report.enabled);
        assert!(dir.join(".offsend/nono/offsend-claude.json").is_file());
        std::env::remove_var("NONO_CAP_FILE");
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn effective_sandbox_enabled_matrix() {
        let on = OffsendProjectConfig::parse_yaml(
            "version: 1\nsandbox:\n  enabled: true\n",
        )
        .unwrap();
        let off = OffsendProjectConfig::parse_yaml(
            "version: 1\nsandbox:\n  enabled: false\n",
        )
        .unwrap();
        let bare = OffsendProjectConfig::parse_yaml("version: 1\n").unwrap();

        assert!(effective_sandbox_enabled(Some(&on), false));
        assert!(effective_sandbox_enabled(Some(&on), true));
        assert!(effective_sandbox_enabled(Some(&off), false)); // ignore loosen
        assert!(!effective_sandbox_enabled(Some(&off), true)); // honor after trust
        assert!(!effective_sandbox_enabled(Some(&bare), false));
        assert!(!effective_sandbox_enabled(None, false));
    }

    #[test]
    fn untrusted_network_allow_forced_to_deny() {
        let cfg = OffsendProjectConfig::parse_yaml(
            r#"
version: 1
sandbox:
  enabled: true
  network:
    default: allow
    allow: [evil.example, api.example]
"#,
        )
        .unwrap();
        let (deny, allow) = network_policy_for_test(Some(&cfg), false);
        assert!(deny);
        assert!(allow.is_empty());

        let (deny_t, allow_t) = network_policy_for_test(Some(&cfg), true);
        assert!(!deny_t);
        assert_eq!(allow_t, vec!["api.example", "evil.example"]); // sorted
    }

    #[test]
    fn untrusted_deny_clears_allow_list_but_keeps_deny() {
        let cfg = OffsendProjectConfig::parse_yaml(
            r#"
version: 1
sandbox:
  enabled: true
  network:
    default: deny
    allow: [ok.example]
"#,
        )
        .unwrap();
        let (deny, allow) = network_policy_for_test(Some(&cfg), false);
        assert!(deny);
        assert!(allow.is_empty());

        let (deny_t, allow_t) = network_policy_for_test(Some(&cfg), true);
        assert!(deny_t);
        assert_eq!(allow_t, vec!["ok.example"]);
    }

    #[test]
    fn sync_profile_blocks_network_when_untrusted_allow() {
        let dir = temp_workdir("net");
        std::env::set_var("NONO_CAP_FILE", "1");
        let cfg = OffsendProjectConfig::parse_yaml(
            r#"
version: 1
sandbox:
  enabled: true
  provider: nono
  network:
    default: allow
"#,
        )
        .unwrap();
        let report = run(&dir, Some(&cfg), EditorTarget::Claude);
        assert!(report.enabled);
        let text = fs::read_to_string(dir.join(".offsend/nono/offsend-claude.json")).unwrap();
        let value: serde_json::Value = serde_json::from_str(&text).unwrap();
        assert_eq!(value["network"]["block"], serde_json::json!(true));
        std::env::remove_var("NONO_CAP_FILE");
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn trusted_enabled_false_skips_sync() {
        let dir = temp_workdir("trusted-off");
        fs::create_dir_all(dir.join(".git")).unwrap();
        let yaml = r#"
version: 1
sandbox:
  enabled: false
  provider: nono
"#;
        fs::write(dir.join(".offsend.yml"), yaml).unwrap();
        crate::policy_trust::trust(&dir).unwrap();
        let cfg = OffsendProjectConfig::parse_yaml(yaml).unwrap();
        let report = run(&dir, Some(&cfg), EditorTarget::Claude);
        assert!(!report.enabled);
        assert!(!dir.join(".offsend/nono/offsend-claude.json").is_file());
        let _ = crate::policy_trust::forget(&dir);
        let _ = fs::remove_dir_all(&dir);
    }
}
