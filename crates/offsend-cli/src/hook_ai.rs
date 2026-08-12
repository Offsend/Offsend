//! AI-editor hook install (cursor, claude, windsurf, codex) — Swift parity.

use serde_json::{json, Map, Value};
use std::fs;
use std::path::{Path, PathBuf};
use thiserror::Error;

pub const AI_MARKER: &str = "offsend-managed-ai-hook";
pub const AI_VERSION: u32 = 8;

const CLAUDE_WRITE_MATCHER: &str = "Edit|MultiEdit|NotebookEdit|Write";
const CLAUDE_MCP_MATCHER: &str = "mcp__.*";
const CURSOR_WRITE_MATCHER: &str = "Write|Edit|Delete";
const CURSOR_TASK_MATCHER: &str = "Task";
const CURSOR_GREP_MATCHER: &str = "Grep";
const CURSOR_MCP_MATCHER: &str = "MCP:.*";
const HOOK_TIMEOUT_SEC: u64 = 30;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum AiTarget {
    Cursor,
    Claude,
    Windsurf,
    Codex,
}

pub const ALL_TARGETS: [AiTarget; 4] = [
    AiTarget::Cursor,
    AiTarget::Claude,
    AiTarget::Windsurf,
    AiTarget::Codex,
];

impl AiTarget {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Cursor => "cursor",
            Self::Claude => "claude",
            Self::Windsurf => "windsurf",
            Self::Codex => "codex",
        }
    }

    pub fn parse(raw: &str) -> Option<Self> {
        match raw {
            "cursor" => Some(Self::Cursor),
            "claude" => Some(Self::Claude),
            "windsurf" => Some(Self::Windsurf),
            "codex" => Some(Self::Codex),
            _ => None,
        }
    }

    pub fn config_path(self, repo: &Path) -> PathBuf {
        match self {
            Self::Cursor => repo.join(".cursor/hooks.json"),
            Self::Claude => repo.join(".claude/settings.json"),
            Self::Windsurf => repo.join(".windsurf/hooks.json"),
            Self::Codex => repo.join(".codex/hooks.json"),
        }
    }

    fn supports_file_gates(self) -> bool {
        matches!(self, Self::Cursor | Self::Claude | Self::Windsurf)
    }
}

#[derive(Debug, Clone, Copy)]
pub struct GateOptions {
    pub read_gate: bool,
    pub write_gate: bool,
    pub shell_gate: bool,
    pub shell_audit: bool,
    pub mcp_gate: bool,
    pub subagent_gate: bool,
    pub mcp_response_gate: bool,
}

impl Default for GateOptions {
    fn default() -> Self {
        Self {
            read_gate: true,
            write_gate: true,
            shell_gate: true,
            shell_audit: true,
            mcp_gate: true,
            subagent_gate: true,
            mcp_response_gate: true,
        }
    }
}

#[derive(Debug, Error)]
pub enum AiHookError {
    #[error("{0}")]
    Message(String),
}

pub fn detected_targets(repo: &Path, home: &Path) -> Vec<AiTarget> {
    let mut targets = vec![AiTarget::Cursor, AiTarget::Claude];
    if repo.join(".windsurf").is_dir() || home.join(".codeium/windsurf").is_dir() {
        targets.push(AiTarget::Windsurf);
    }
    if repo.join(".codex").is_dir() || home.join(".codex").is_dir() {
        targets.push(AiTarget::Codex);
    }
    targets
}

pub fn wrapper_command(cli_path: &str, adapter: &str, extra_args: &[&str]) -> String {
    let mut args = vec!["check".to_string(), "--adapter".into(), adapter.to_string()];
    args.extend(extra_args.iter().map(|s| (*s).to_string()));
    let joined = args
        .iter()
        .map(|a| shell_quote(a))
        .collect::<Vec<_>>()
        .join(" ");
    format!(
        "OFFSEND_MANAGED_HOOK=1 sh -c 'BIN=\"$1\"; shift; if [ ! -x \"$BIN\" ]; then BIN=\"$(command -v offsend 2>/dev/null || true)\"; fi; if [ -z \"$BIN\" ] || [ ! -x \"$BIN\" ]; then echo \"offsend: executable not found; install CLI or re-run hook install\" >&2; exit 127; fi; exec \"$BIN\" \"$@\"' sh {bin} {joined}",
        bin = shell_quote(cli_path),
        joined = joined
    )
}

pub fn install(
    target: AiTarget,
    repo: &Path,
    cli_path: &str,
    hook_policy: &str,
    gates: &GateOptions,
) -> Result<PathBuf, AiHookError> {
    let path = target.config_path(repo);
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent).map_err(|e| AiHookError::Message(e.to_string()))?;
    }
    let mut root = load_json(&path).unwrap_or_else(|| match target {
        AiTarget::Cursor => json!({ "version": 1 }),
        _ => json!({}),
    });
    if !root.is_object() {
        root = match target {
            AiTarget::Cursor => json!({ "version": 1 }),
            _ => json!({}),
        };
    }

    let prompt_cmd = wrapper_command(
        cli_path,
        target.as_str(),
        &["--hook-policy", hook_policy, "--no-notify"],
    );

    let file_gates = target.supports_file_gates();
    let enable_read = file_gates && gates.read_gate;
    let enable_write = file_gates && gates.write_gate;
    let enable_shell = file_gates && gates.shell_gate;
    let enable_shell_audit = file_gates && gates.shell_audit;
    let enable_mcp = file_gates && gates.mcp_gate;
    let enable_mcp_response = file_gates && gates.mcp_response_gate;
    let enable_artifact = file_gates;
    let enable_grep = enable_read && matches!(target, AiTarget::Cursor);
    let enable_subagent = gates.subagent_gate && matches!(target, AiTarget::Cursor);

    match target {
        AiTarget::Cursor => merge_cursor(
            &mut root,
            &prompt_cmd,
            cli_path,
            enable_read,
            enable_grep,
            enable_write,
            enable_artifact,
            enable_shell,
            enable_shell_audit,
            enable_mcp,
            enable_subagent,
            enable_mcp_response,
        )?,
        AiTarget::Claude => merge_claude(
            &mut root,
            &prompt_cmd,
            cli_path,
            enable_read,
            enable_write,
            enable_artifact,
            enable_shell,
            enable_shell_audit,
            enable_mcp,
            enable_mcp_response,
        )?,
        AiTarget::Windsurf => merge_windsurf(
            &mut root,
            &prompt_cmd,
            cli_path,
            enable_read,
            enable_write,
            enable_artifact,
            enable_shell,
            enable_shell_audit,
            enable_mcp,
            enable_mcp_response,
        )?,
        AiTarget::Codex => merge_codex(&mut root, &prompt_cmd)?,
    }

    write_json(&path, &root)?;
    Ok(path)
}

pub fn uninstall(target: AiTarget, repo: &Path) -> Result<bool, AiHookError> {
    let path = target.config_path(repo);
    let Some(mut root) = load_json(&path) else {
        return Ok(false);
    };
    let removed = match target {
        AiTarget::Cursor | AiTarget::Windsurf => remove_managed_flat(&mut root),
        AiTarget::Claude | AiTarget::Codex => remove_managed_nested(&mut root),
    };
    if removed {
        write_json(&path, &root)?;
    }
    Ok(removed)
}

pub fn is_installed(target: AiTarget, repo: &Path) -> bool {
    let path = target.config_path(repo);
    let Some(root) = load_json(&path) else {
        return false;
    };
    root.get("_offsend")
        .and_then(|v| v.get("managed"))
        .and_then(|v| v.as_bool())
        .unwrap_or(false)
}

fn merge_cursor(
    root: &mut Value,
    prompt_cmd: &str,
    cli_path: &str,
    enable_read: bool,
    enable_grep: bool,
    enable_write: bool,
    enable_artifact: bool,
    enable_shell: bool,
    enable_shell_audit: bool,
    enable_mcp: bool,
    enable_subagent: bool,
    enable_mcp_response: bool,
) -> Result<(), AiHookError> {
    let hooks = root
        .as_object_mut()
        .ok_or_else(|| AiHookError::Message("invalid hooks.json".into()))?
        .entry("hooks")
        .or_insert_with(|| json!({}));
    let hooks_obj = hooks
        .as_object_mut()
        .ok_or_else(|| AiHookError::Message("invalid hooks object".into()))?;

    set_cursor_event(hooks_obj, "beforeSubmitPrompt", Some(prompt_cmd), false, None);

    let read = enable_read.then(|| {
        wrapper_command(cli_path, "cursor", &["--read-gate", "--no-notify"])
    });
    set_cursor_event(
        hooks_obj,
        "beforeReadFile",
        read.as_deref(),
        false,
        None,
    );

    let grep = enable_grep.then(|| {
        wrapper_command(
            cli_path,
            "cursor",
            &["--grep-gate", "--no-notify"],
        )
    });
    set_cursor_event(
        hooks_obj,
        "preToolUse",
        grep.as_deref(),
        true,
        Some(CURSOR_GREP_MATCHER),
    );

    let write = enable_write.then(|| {
        wrapper_command(cli_path, "cursor", &["--write-gate", "--no-notify"])
    });
    set_cursor_event(
        hooks_obj,
        "preToolUse",
        write.as_deref(),
        true,
        Some(CURSOR_WRITE_MATCHER),
    );

    let task = enable_subagent.then(|| {
        wrapper_command(
            cli_path,
            "cursor",
            &["--subagent-gate", "--no-notify"],
        )
    });
    set_cursor_event(
        hooks_obj,
        "preToolUse",
        task.as_deref(),
        true,
        Some(CURSOR_TASK_MATCHER),
    );
    set_cursor_event(hooks_obj, "subagentStart", task.as_deref(), true, None);

    let artifact = enable_artifact.then(|| {
        wrapper_command(cli_path, "cursor", &["--artifact-audit", "--no-notify"])
    });
    set_cursor_event(
        hooks_obj,
        "afterFileEdit",
        artifact.as_deref(),
        false,
        None,
    );

    let shell = enable_shell.then(|| {
        wrapper_command(cli_path, "cursor", &["--shell-gate", "--no-notify"])
    });
    set_cursor_event(
        hooks_obj,
        "beforeShellExecution",
        shell.as_deref(),
        true,
        None,
    );

    let shell_audit = enable_shell_audit.then(|| {
        wrapper_command(
            cli_path,
            "cursor",
            &["--shell-audit", "--no-notify"],
        )
    });
    set_cursor_event(
        hooks_obj,
        "afterShellExecution",
        shell_audit.as_deref(),
        false,
        None,
    );

    let mcp = enable_mcp.then(|| {
        wrapper_command(
            cli_path,
            "cursor",
            &["--mcp-gate", "--no-notify"],
        )
    });
    set_cursor_event(
        hooks_obj,
        "beforeMCPExecution",
        mcp.as_deref(),
        true,
        None,
    );

    // Remove legacy observe-only MCP response hook.
    set_cursor_event(hooks_obj, "afterMCPExecution", None, false, None);

    let mcp_resp = enable_mcp_response.then(|| {
        wrapper_command(
            cli_path,
            "cursor",
            &["--mcp-response-gate", "--no-notify"],
        )
    });
    set_cursor_event(
        hooks_obj,
        "postToolUse",
        mcp_resp.as_deref(),
        false,
        Some(CURSOR_MCP_MATCHER),
    );

    root.as_object_mut()
        .unwrap()
        .insert("_offsend".into(), managed_meta("beforeSubmitPrompt"));
    if root.get("version").is_none() {
        root.as_object_mut()
            .unwrap()
            .insert("version".into(), json!(1));
    }
    Ok(())
}

fn merge_claude(
    root: &mut Value,
    prompt_cmd: &str,
    cli_path: &str,
    enable_read: bool,
    enable_write: bool,
    enable_artifact: bool,
    enable_shell: bool,
    enable_shell_audit: bool,
    enable_mcp: bool,
    enable_mcp_response: bool,
) -> Result<(), AiHookError> {
    let hooks = root
        .as_object_mut()
        .ok_or_else(|| AiHookError::Message("invalid settings.json".into()))?
        .entry("hooks")
        .or_insert_with(|| json!({}));
    let hooks_obj = hooks
        .as_object_mut()
        .ok_or_else(|| AiHookError::Message("invalid hooks object".into()))?;

    let mut prompt_groups = remove_managed_from_groups(hooks_obj.get("UserPromptSubmit"));
    prompt_groups.push(claude_command_group(prompt_cmd, None));
    hooks_obj.insert("UserPromptSubmit".into(), Value::Array(prompt_groups));

    let mut tool_groups = remove_managed_from_groups(hooks_obj.get("PreToolUse"));
    if enable_read {
        let cmd = wrapper_command(cli_path, "claude", &["--read-gate", "--no-notify"]);
        tool_groups.push(claude_command_group(&cmd, Some("Read")));
    }
    if enable_write {
        let cmd = wrapper_command(cli_path, "claude", &["--write-gate", "--no-notify"]);
        tool_groups.push(claude_command_group(&cmd, Some(CLAUDE_WRITE_MATCHER)));
    }
    if enable_shell {
        let cmd = wrapper_command(cli_path, "claude", &["--shell-gate", "--no-notify"]);
        tool_groups.push(claude_command_group(&cmd, Some("Bash")));
    }
    if enable_mcp {
        let cmd = wrapper_command(
            cli_path,
            "claude",
            &["--mcp-gate", "--no-notify"],
        );
        tool_groups.push(claude_command_group(&cmd, Some(CLAUDE_MCP_MATCHER)));
    }
    if tool_groups.is_empty() {
        hooks_obj.remove("PreToolUse");
    } else {
        hooks_obj.insert("PreToolUse".into(), Value::Array(tool_groups));
    }

    let mut post_groups = remove_managed_from_groups(hooks_obj.get("PostToolUse"));
    if enable_mcp_response {
        let cmd = wrapper_command(
            cli_path,
            "claude",
            &["--mcp-response-gate", "--no-notify"],
        );
        post_groups.push(claude_command_group(&cmd, Some(CLAUDE_MCP_MATCHER)));
    }
    if enable_artifact {
        let cmd = wrapper_command(cli_path, "claude", &["--artifact-audit", "--no-notify"]);
        post_groups.push(claude_command_group(&cmd, Some(CLAUDE_WRITE_MATCHER)));
    }
    if enable_shell_audit {
        let cmd = wrapper_command(
            cli_path,
            "claude",
            &["--shell-audit", "--no-notify"],
        );
        post_groups.push(claude_command_group(&cmd, Some("Bash")));
    }
    if post_groups.is_empty() {
        hooks_obj.remove("PostToolUse");
    } else {
        hooks_obj.insert("PostToolUse".into(), Value::Array(post_groups));
    }

    root.as_object_mut()
        .unwrap()
        .insert("_offsend".into(), managed_meta("UserPromptSubmit"));
    Ok(())
}

fn merge_windsurf(
    root: &mut Value,
    prompt_cmd: &str,
    cli_path: &str,
    enable_read: bool,
    enable_write: bool,
    enable_artifact: bool,
    enable_shell: bool,
    enable_shell_audit: bool,
    enable_mcp: bool,
    enable_mcp_response: bool,
) -> Result<(), AiHookError> {
    let hooks = root
        .as_object_mut()
        .ok_or_else(|| AiHookError::Message("invalid hooks.json".into()))?
        .entry("hooks")
        .or_insert_with(|| json!({}));
    let hooks_obj = hooks
        .as_object_mut()
        .ok_or_else(|| AiHookError::Message("invalid hooks object".into()))?;

    set_windsurf_event(hooks_obj, "pre_user_prompt", Some(prompt_cmd), true);

    let read = enable_read.then(|| {
        wrapper_command(cli_path, "windsurf", &["--read-gate", "--no-notify"])
    });
    set_windsurf_event(hooks_obj, "pre_read_code", read.as_deref(), false);

    let write = enable_write.then(|| {
        wrapper_command(cli_path, "windsurf", &["--write-gate", "--no-notify"])
    });
    set_windsurf_event(hooks_obj, "pre_write_code", write.as_deref(), false);

    let artifact = enable_artifact.then(|| {
        wrapper_command(
            cli_path,
            "windsurf",
            &["--artifact-audit", "--no-notify"],
        )
    });
    set_windsurf_event(hooks_obj, "post_write_code", artifact.as_deref(), false);

    let shell = enable_shell.then(|| {
        wrapper_command(cli_path, "windsurf", &["--shell-gate", "--no-notify"])
    });
    set_windsurf_event(hooks_obj, "pre_run_command", shell.as_deref(), false);

    let shell_audit = enable_shell_audit.then(|| {
        wrapper_command(
            cli_path,
            "windsurf",
            &["--shell-audit", "--no-notify"],
        )
    });
    set_windsurf_event(
        hooks_obj,
        "post_run_command",
        shell_audit.as_deref(),
        false,
    );

    let mcp = enable_mcp.then(|| {
        wrapper_command(cli_path, "windsurf", &["--mcp-gate", "--no-notify"])
    });
    set_windsurf_event(hooks_obj, "pre_mcp_tool_use", mcp.as_deref(), false);

    let mcp_resp = enable_mcp_response.then(|| {
        wrapper_command(
            cli_path,
            "windsurf",
            &["--mcp-response-gate", "--no-notify"],
        )
    });
    set_windsurf_event(
        hooks_obj,
        "post_mcp_tool_use",
        mcp_resp.as_deref(),
        false,
    );

    root.as_object_mut()
        .unwrap()
        .insert("_offsend".into(), managed_meta("pre_user_prompt"));
    Ok(())
}

/// Adds/refreshes a managed Windsurf gate, or removes it when `command` is None.
fn set_windsurf_event(
    hooks: &mut Map<String, Value>,
    event: &str,
    command: Option<&str>,
    show_output: bool,
) {
    let mut entries = hooks
        .get(event)
        .and_then(|v| v.as_array())
        .cloned()
        .unwrap_or_default();
    entries.retain(|e| !is_managed_entry(e));
    if let Some(command) = command {
        entries.push(json!({
            "command": command,
            "show_output": show_output
        }));
        hooks.insert(event.into(), Value::Array(entries));
    } else if entries.is_empty() {
        hooks.remove(event);
    } else {
        hooks.insert(event.into(), Value::Array(entries));
    }
}

fn merge_codex(root: &mut Value, prompt_cmd: &str) -> Result<(), AiHookError> {
    let hooks = root
        .as_object_mut()
        .ok_or_else(|| AiHookError::Message("invalid hooks.json".into()))?
        .entry("hooks")
        .or_insert_with(|| json!({}));
    let hooks_obj = hooks
        .as_object_mut()
        .ok_or_else(|| AiHookError::Message("invalid hooks object".into()))?;

    let event = "UserPromptSubmit";
    let mut groups = remove_managed_from_groups(hooks_obj.get(event));
    groups.push(json!({
        "hooks": [{
            "type": "command",
            "command": prompt_cmd,
            "timeoutSec": HOOK_TIMEOUT_SEC,
            "statusMessage": "Offsend prompt check"
        }]
    }));
    hooks_obj.insert(event.into(), Value::Array(groups));

    root.as_object_mut()
        .unwrap()
        .insert("_offsend".into(), managed_meta(event));
    Ok(())
}

/// Adds/refreshes a managed Cursor gate, or removes it when `command` is None.
fn set_cursor_event(
    hooks: &mut Map<String, Value>,
    event: &str,
    command: Option<&str>,
    fail_closed: bool,
    matcher: Option<&str>,
) {
    let mut entries = hooks
        .get(event)
        .and_then(|v| v.as_array())
        .cloned()
        .unwrap_or_default();
    entries.retain(|e| {
        if !is_managed_entry(e) {
            return true;
        }
        match (matcher, e.get("matcher").and_then(|m| m.as_str())) {
            (Some(want), Some(have)) => have != want,
            (None, None) => false,
            (Some(_), None) | (None, Some(_)) => true,
        }
    });
    if let Some(command) = command {
        let mut entry = json!({
            "command": command,
            "failClosed": fail_closed,
            "timeout": HOOK_TIMEOUT_SEC
        });
        if let Some(m) = matcher {
            entry
                .as_object_mut()
                .unwrap()
                .insert("matcher".into(), json!(m));
        }
        entries.push(entry);
        hooks.insert(event.into(), Value::Array(entries));
    } else if entries.is_empty() {
        hooks.remove(event);
    } else {
        hooks.insert(event.into(), Value::Array(entries));
    }
}

fn claude_command_group(command: &str, matcher: Option<&str>) -> Value {
    let mut group = json!({
        "hooks": [{
            "type": "command",
            "command": command,
            "timeout": HOOK_TIMEOUT_SEC
        }]
    });
    if let Some(m) = matcher {
        group
            .as_object_mut()
            .unwrap()
            .insert("matcher".into(), json!(m));
    }
    group
}

fn remove_managed_from_groups(existing: Option<&Value>) -> Vec<Value> {
    let Some(arr) = existing.and_then(|v| v.as_array()) else {
        return Vec::new();
    };
    arr.iter()
        .filter_map(|group| {
            let Some(nested) = group.get("hooks").and_then(|h| h.as_array()) else {
                return Some(group.clone());
            };
            let kept: Vec<Value> = nested
                .iter()
                .filter(|h| !is_managed_entry(h))
                .cloned()
                .collect();
            if kept.is_empty() {
                return None;
            }
            let mut copy = group.clone();
            copy.as_object_mut()
                .unwrap()
                .insert("hooks".into(), Value::Array(kept));
            Some(copy)
        })
        .collect()
}

fn remove_managed_flat(root: &mut Value) -> bool {
    let Some(hooks) = root.get_mut("hooks").and_then(|h| h.as_object_mut()) else {
        return root
            .as_object_mut()
            .map(|o| o.remove("_offsend").is_some())
            .unwrap_or(false);
    };
    let mut changed = false;
    let keys: Vec<_> = hooks.keys().cloned().collect();
    for key in keys {
        if let Some(arr) = hooks.get_mut(&key).and_then(|v| v.as_array_mut()) {
            let before = arr.len();
            arr.retain(|e| !is_managed_entry(e));
            if arr.len() != before {
                changed = true;
            }
            if arr.is_empty() {
                hooks.remove(&key);
            }
        }
    }
    if root
        .as_object_mut()
        .map(|o| o.remove("_offsend").is_some())
        .unwrap_or(false)
    {
        changed = true;
    }
    changed
}

fn remove_managed_nested(root: &mut Value) -> bool {
    let Some(hooks) = root.get_mut("hooks").and_then(|h| h.as_object_mut()) else {
        return root
            .as_object_mut()
            .map(|o| o.remove("_offsend").is_some())
            .unwrap_or(false);
    };
    let mut changed = false;
    let keys: Vec<_> = hooks.keys().cloned().collect();
    for key in keys {
        let Some(arr) = hooks.get(&key).and_then(|v| v.as_array()) else {
            continue;
        };
        let before = arr.len();
        let cleaned = remove_managed_from_groups(Some(&Value::Array(arr.clone())));
        if cleaned.len() != before || cleaned.iter().zip(arr.iter()).any(|(a, b)| a != b) {
            changed = true;
        }
        if cleaned.is_empty() {
            hooks.remove(&key);
        } else {
            hooks.insert(key, Value::Array(cleaned));
        }
    }
    if root
        .as_object_mut()
        .map(|o| o.remove("_offsend").is_some())
        .unwrap_or(false)
    {
        changed = true;
    }
    changed
}

fn is_managed_entry(entry: &Value) -> bool {
    entry
        .get("command")
        .and_then(|c| c.as_str())
        .map(|c| c.contains("OFFSEND_MANAGED_HOOK=1"))
        .unwrap_or(false)
}

fn managed_meta(event: &str) -> Value {
    json!({
        "event": event,
        "managed": true,
        "marker": AI_MARKER,
        "version": AI_VERSION
    })
}

fn load_json(path: &Path) -> Option<Value> {
    let data = fs::read_to_string(path).ok()?;
    serde_json::from_str(&data).ok()
}

/// Writes only when the serialized JSON differs from what is on disk, so a
/// repeated `offsend sync` is a no-op (no mtime churn, no editor-settings
/// rewrite). Returns whether the file was written.
fn write_json(path: &Path, value: &Value) -> Result<bool, AiHookError> {
    let mut text =
        serde_json::to_string_pretty(value).map_err(|e| AiHookError::Message(e.to_string()))?;
    text.push('\n');
    if fs::read_to_string(path).is_ok_and(|current| current == text) {
        return Ok(false);
    }
    fs::write(path, text).map_err(|e| AiHookError::Message(e.to_string()))?;
    Ok(true)
}

fn shell_quote(value: &str) -> String {
    if value
        .chars()
        .all(|c| c.is_ascii_alphanumeric() || matches!(c, '_' | '.' | '/' | ':' | '-'))
    {
        value.to_string()
    } else {
        format!("'{}'", value.replace('\'', "'\\''"))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::time::{SystemTime, UNIX_EPOCH};

    fn tmp_repo() -> PathBuf {
        let nanos = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        let dir = std::env::temp_dir().join(format!("offsend-windsurf-hooks-{nanos}"));
        fs::create_dir_all(dir.join(".windsurf")).unwrap();
        dir
    }

    #[test]
    fn windsurf_install_writes_file_gates() {
        let repo = tmp_repo();
        let path = install(
            AiTarget::Windsurf,
            &repo,
            "/usr/local/bin/offsend",
            "soft-block",
            &GateOptions::default(),
        )
        .unwrap();
        let root: Value = serde_json::from_str(&fs::read_to_string(&path).unwrap()).unwrap();
        let hooks = root.get("hooks").and_then(|h| h.as_object()).unwrap();
        for event in [
            "pre_user_prompt",
            "pre_read_code",
            "pre_write_code",
            "post_write_code",
            "pre_run_command",
            "post_run_command",
            "pre_mcp_tool_use",
            "post_mcp_tool_use",
        ] {
            assert!(
                hooks.get(event).and_then(|v| v.as_array()).is_some_and(|a| {
                    a.iter().any(is_managed_entry)
                }),
                "missing managed hook for {event}"
            );
        }
        assert_eq!(
            root.pointer("/_offsend/version").and_then(|v| v.as_u64()),
            Some(AI_VERSION as u64)
        );
        let _ = fs::remove_dir_all(&repo);
    }

    #[test]
    fn install_is_idempotent() {
        let repo = tmp_repo();
        let path = install(
            AiTarget::Windsurf,
            &repo,
            "/usr/local/bin/offsend",
            "soft-block",
            &GateOptions::default(),
        )
        .unwrap();
        let first = fs::read_to_string(&path).unwrap();
        let root: Value = serde_json::from_str(&first).unwrap();
        assert!(
            !write_json(&path, &root).unwrap(),
            "identical content must not be rewritten"
        );
        install(
            AiTarget::Windsurf,
            &repo,
            "/usr/local/bin/offsend",
            "soft-block",
            &GateOptions::default(),
        )
        .unwrap();
        assert_eq!(fs::read_to_string(&path).unwrap(), first);
        let _ = fs::remove_dir_all(&repo);
    }

    #[test]
    fn windsurf_supports_file_gates() {
        assert!(AiTarget::Windsurf.supports_file_gates());
        assert!(!AiTarget::Codex.supports_file_gates());
    }
}
