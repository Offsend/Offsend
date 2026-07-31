//! `--subagent-gate` (Cursor)

use super::render::{self, Permission};
use super::Adapter;
use offsend_detect::{DetectionEngine, DetectionRequest};
use serde_json::Value;
use std::io::{self, Write};
use std::process::ExitCode;

#[derive(Clone, Copy)]
enum Mode {
    Observe,
    Ask,
    Deny,
}

pub fn run(
    adapter: Adapter,
    secrets_only: bool,
    stdin: &str,
    mode_raw: Option<&str>,
    scan_task: bool,
) -> ExitCode {
    if !matches!(adapter, Adapter::Cursor) {
        // Claude/others: empty stub per Swift
        return ExitCode::SUCCESS;
    }
    let mode = match mode_raw.unwrap_or("deny") {
        "observe" => Mode::Observe,
        "ask" => Mode::Ask,
        _ => Mode::Deny,
    };

    if !scan_task {
        return render::permission_response(adapter, Permission::Allow, None, None);
    }

    if stdin.len() > crate::io::MAX_INPUT_BYTES {
        return match mode {
            Mode::Observe => {
                render::fail_open(adapter, "stdin_too_large", render::GateKind::Permission)
            }
            _ => render::permission_response(
                adapter,
                Permission::Deny,
                Some("Offsend: subagent hook input exceeds safety limit."),
                None,
            ),
        };
    }
    let root: Value = match serde_json::from_str(stdin) {
        Ok(v) => v,
        Err(_) => {
            return match mode {
                Mode::Observe => {
                    render::fail_open(adapter, "invalid_json", render::GateKind::Permission)
                }
                _ => render::permission_response(
                    adapter,
                    Permission::Deny,
                    Some("Offsend: unrecognized subagent-gate input denied."),
                    None,
                ),
            }
        }
    };

    let task = extract_task(&root).unwrap_or_default();
    let result = DetectionEngine::scan(&DetectionRequest::new(task));
    let secrets: Vec<_> = result
        .entities
        .into_iter()
        .filter(|e| {
            if secrets_only {
                e.entity_type.counts_as_critical_secret()
            } else {
                true
            }
        })
        .collect();

    if secrets.is_empty() {
        return render::permission_response(adapter, Permission::Allow, None, None);
    }

    let reason = format!(
        "Offsend blocked this subagent: task contains {} sensitive finding(s).",
        secrets.len()
    );
    match mode {
        Mode::Observe => {
            let _ = writeln!(io::stderr(), "offsend: subagent-gate: {reason}");
            render::permission_response(adapter, Permission::Allow, None, None)
        }
        // Cursor cannot ask on subagentStart — deny.
        Mode::Ask | Mode::Deny => {
            render::permission_response(adapter, Permission::Deny, Some(&reason), None)
        }
    }
}

fn extract_task(root: &Value) -> Option<String> {
    let tool = root.get("tool_input").or_else(|| root.get("toolInput"));
    for src in [Some(root), tool].into_iter().flatten() {
        for key in ["task", "prompt", "description"] {
            if let Some(s) = src.get(key).and_then(|v| v.as_str()) {
                if !s.is_empty() {
                    return Some(s.to_string());
                }
            }
        }
    }
    None
}
