//! AI-editor hook adapters for `check --adapter`.

mod artifact_audit;
mod artifacts;
mod grep;
mod mcp;
mod prompt;
mod read;
mod render;
mod seal_copy;
mod sensitive;
mod shell;
mod shell_audit;
mod subagent;
mod write;

pub use render::{fail_open, GateKind};

use serde_json::Value;
use std::io::{self, Read, Write};
use std::path::{Path, PathBuf};
use std::process::ExitCode;

#[derive(Clone, Copy)]
pub enum Adapter {
    Cursor,
    Claude,
    Windsurf,
    Codex,
}

impl Adapter {
    pub fn parse(raw: &str) -> Option<Self> {
        match raw {
            "cursor" => Some(Self::Cursor),
            "claude" => Some(Self::Claude),
            "windsurf" => Some(Self::Windsurf),
            "codex" => Some(Self::Codex),
            _ => None,
        }
    }

    pub fn as_str(self) -> &'static str {
        match self {
            Self::Cursor => "cursor",
            Self::Claude => "claude",
            Self::Windsurf => "windsurf",
            Self::Codex => "codex",
        }
    }
}

#[derive(Clone, Copy)]
pub enum HookPolicy {
    Advise,
    SoftBlock,
    Block,
}

impl HookPolicy {
    pub fn parse(raw: &str) -> Option<Self> {
        match raw {
            "advise" => Some(Self::Advise),
            "soft-block" => Some(Self::SoftBlock),
            "block" => Some(Self::Block),
            _ => None,
        }
    }
}

pub struct AdapterFlags {
    pub adapter: Adapter,
    pub hook_policy: HookPolicy,
    pub secrets_only: bool,
    pub seal_copy: bool,
    pub key_file: Option<String>,
    pub key_name: Option<String>,
    pub read_gate: bool,
    pub write_gate: bool,
    pub shell_gate: bool,
    pub shell_audit: bool,
    pub mcp_gate: bool,
    pub mcp_response_gate: bool,
    pub subagent_gate: bool,
    pub artifact_audit: bool,
    pub grep_gate: bool,
    pub context: Option<Value>,
    pub exclude_patterns: Vec<String>,
    pub ignore_patterns: Vec<String>,
    pub project_root: PathBuf,
    /// When true, shell-gate denies (or asks) commands the editor reports as unsandboxed.
    pub sandbox_required: bool,
}

pub fn run(flags: AdapterFlags) -> Result<ExitCode, String> {
    // Policy trust is enforced before consuming stdin (Swift parity).
    let trusted = match crate::policy_trust::status(&flags.project_root) {
        crate::policy_trust::TrustStatus::Drift(reason)
        | crate::policy_trust::TrustStatus::Invalid(reason) => {
            return Ok(fail_closed_policy(flags.adapter, gate_kind(&flags), &reason));
        }
        crate::policy_trust::TrustStatus::Trusted => true,
        crate::policy_trust::TrustStatus::Missing => false,
    };

    let mut buf = Vec::new();
    io::stdin()
        .take((crate::io::MAX_INPUT_BYTES as u64) + 1)
        .read_to_end(&mut buf)
        .map_err(|e| e.to_string())?;
    let oversized = buf.len() > crate::io::MAX_INPUT_BYTES;
    let stdin = if oversized {
        String::from_utf8_lossy(&buf[..crate::io::MAX_INPUT_BYTES.min(buf.len())]).into_owned()
    } else {
        String::from_utf8(buf).map_err(|_| "stdin_not_utf8".to_string())?
    };
    let stdin_for_gate = if oversized {
        let mut s = stdin;
        s.push('\0');
        s
    } else {
        stdin
    };

    // Until trusted, ignore fields that can loosen gates (check.exclude, ask modes, …).
    let exclude_patterns: &[String] = if trusted {
        &flags.exclude_patterns
    } else {
        &[]
    };
    let shell_mode = if trusted {
        context_str(&flags.context, &["shell", "mode"])
    } else {
        None
    };
    // `context.mcp.mode: deny` tightens the default (ask); observe/ask-from-config
    // can loosen and need a trusted snapshot. Server allow/deny lists always apply.
    let mcp_mode = match context_str(&flags.context, &["mcp", "mode"]).as_deref() {
        Some("deny") => Some("deny".to_string()),
        Some(other) if trusted => Some(other.to_string()),
        _ => None,
    };
    let mcp_allow = context_str_list(&flags.context, &["mcp", "allow"]);
    let mcp_deny = context_str_list(&flags.context, &["mcp", "deny"]);
    let mcp_responses = context_str(&flags.context, &["mcp", "responses"]);
    let subagents_mode = match context_str(&flags.context, &["subagents", "mode"]).as_deref() {
        Some("deny") => Some("deny".to_string()),
        Some(other) if trusted => Some(other.to_string()),
        _ => None,
    };
    let scan_task = if trusted {
        context_bool(&flags.context, &["subagents", "scan_task"]).unwrap_or(true)
    } else {
        true
    };
    let on_secret_seal =
        context_str(&flags.context, &["read", "on_secret"]).as_deref() == Some("seal");

    let code = if flags.read_gate {
        read::run(
            flags.adapter,
            flags.secrets_only,
            &stdin_for_gate,
            exclude_patterns,
            Some(Path::new(&flags.project_root)),
            on_secret_seal,
            flags.key_file.as_deref(),
            flags.key_name.as_deref(),
        )
    } else if flags.grep_gate {
        grep::run(
            flags.adapter,
            flags.secrets_only,
            &stdin_for_gate,
            on_secret_seal,
        )
    } else if flags.write_gate {
        write::run(flags.adapter, &stdin_for_gate)
    } else if flags.shell_gate {
        shell::run(
            flags.adapter,
            &stdin_for_gate,
            shell_mode.as_deref(),
            &flags.ignore_patterns,
            Some(Path::new(&flags.project_root)),
            flags.sandbox_required,
        )
    } else if flags.shell_audit {
        shell_audit::run(flags.adapter, flags.secrets_only, &stdin_for_gate)
    } else if flags.mcp_gate {
        mcp::run_call(
            flags.adapter,
            flags.secrets_only,
            &stdin_for_gate,
            mcp_mode.as_deref(),
            &mcp_allow,
            &mcp_deny,
        )
    } else if flags.mcp_response_gate {
        mcp::run_response(
            flags.adapter,
            flags.secrets_only,
            &stdin_for_gate,
            mcp_responses.as_deref(),
        )
    } else if flags.subagent_gate {
        subagent::run(
            flags.adapter,
            flags.secrets_only,
            &stdin_for_gate,
            subagents_mode.as_deref(),
            scan_task,
        )
    } else if flags.artifact_audit {
        artifact_audit::run(flags.adapter, &stdin_for_gate)
    } else {
        prompt::run(
            flags.adapter,
            flags.hook_policy,
            flags.secrets_only,
            flags.seal_copy,
            flags.key_file.as_deref(),
            flags.key_name.as_deref(),
            &flags.project_root,
            &stdin_for_gate,
            exclude_patterns,
        )
    };
    Ok(code)
}

/// Which response shape the active gate expects. Drift/invalid-policy denies must
/// be rendered in this shape, otherwise editors ignore the deny and fail open
/// (e.g. a `PreToolUse` permission shape emitted on a prompt event is dropped).
fn gate_kind(flags: &AdapterFlags) -> GateKind {
    if flags.read_gate
        || flags.grep_gate
        || flags.write_gate
        || flags.shell_gate
        || flags.mcp_gate
        || flags.mcp_response_gate
        || flags.subagent_gate
    {
        GateKind::Permission
    } else if flags.shell_audit || flags.artifact_audit {
        GateKind::Observe
    } else {
        GateKind::Prompt
    }
}

fn fail_closed_policy(adapter: Adapter, kind: GateKind, reason: &str) -> ExitCode {
    let message = format!(
        "Offsend blocked this operation: {reason}. Review .offsend.yml, then run `offsend policy trust` yourself in a terminal."
    );
    let _ = writeln!(
        io::stderr(),
        "offsend: fail-closed ({}): policy_drift",
        adapter.as_str()
    );
    match kind {
        GateKind::Prompt => render::prompt_deny(adapter, &message),
        GateKind::Permission => render::permission_response(
            adapter,
            render::Permission::Deny,
            Some(&message),
            Some(&message),
        ),
        // Observational gates (shell-audit, artifact-audit) run post-hoc and
        // cannot block; emit the neutral shape rather than a bogus deny.
        GateKind::Observe => render::empty_ok(),
    }
}

fn context_str(context: &Option<Value>, path: &[&str]) -> Option<String> {
    let mut cur = context.as_ref()?;
    for key in path {
        cur = cur.get(*key)?;
    }
    cur.as_str().map(str::to_string)
}

fn context_str_list(context: &Option<Value>, path: &[&str]) -> Vec<String> {
    let mut cur = context.as_ref();
    for key in path {
        cur = cur.and_then(|v| v.get(*key));
    }
    cur.and_then(|v| v.as_array())
        .map(|arr| {
            arr.iter()
                .filter_map(|v| v.as_str().map(str::to_string))
                .collect()
        })
        .unwrap_or_default()
}

fn context_bool(context: &Option<Value>, path: &[&str]) -> Option<bool> {
    let mut cur = context.as_ref()?;
    for key in path {
        cur = cur.get(*key)?;
    }
    cur.as_bool()
}
