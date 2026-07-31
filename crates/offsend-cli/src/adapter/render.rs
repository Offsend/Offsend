//! Shared adapter response JSON shapes.

use serde_json::json;
use std::io::{self, Write};
use std::process::ExitCode;

use super::Adapter;

#[derive(Clone, Copy, PartialEq, Eq)]
pub enum Permission {
    Allow,
    Ask,
    Deny,
}

pub fn print_json(value: &serde_json::Value) {
    let _ = writeln!(io::stdout(), "{value}");
}

pub fn prompt_allow(adapter: Adapter) -> ExitCode {
    match adapter {
        Adapter::Cursor => print_json(&json!({"continue": true})),
        Adapter::Claude | Adapter::Codex => print_json(&json!({})),
        Adapter::Windsurf => {}
    }
    ExitCode::SUCCESS
}

pub fn prompt_deny(adapter: Adapter, message: &str) -> ExitCode {
    match adapter {
        Adapter::Cursor => print_json(&json!({
            "continue": false,
            "user_message": message,
        })),
        Adapter::Claude | Adapter::Codex => print_json(&json!({
            "decision": "block",
            "reason": message,
            "systemMessage": message,
        })),
        Adapter::Windsurf => {
            let _ = writeln!(io::stderr(), "{message}");
            return ExitCode::from(2);
        }
    }
    ExitCode::SUCCESS
}

pub fn prompt_advise(adapter: Adapter, message: &str) -> ExitCode {
    match adapter {
        Adapter::Cursor => {
            let _ = writeln!(io::stderr(), "offsend: advise: {message}");
            print_json(&json!({"continue": true}));
        }
        Adapter::Claude | Adapter::Codex => print_json(&json!({"systemMessage": message})),
        Adapter::Windsurf => {
            let _ = writeln!(io::stderr(), "{message}");
        }
    }
    ExitCode::SUCCESS
}

pub fn permission_response(
    adapter: Adapter,
    permission: Permission,
    user_message: Option<&str>,
    agent_message: Option<&str>,
) -> ExitCode {
    match adapter {
        Adapter::Cursor => match permission {
            Permission::Allow => print_json(&json!({"permission": "allow"})),
            Permission::Ask => {
                let mut obj = json!({
                    "permission": "ask",
                    "user_message": user_message.unwrap_or("Offsend asks for confirmation."),
                });
                if let Some(agent) = agent_message {
                    obj.as_object_mut()
                        .unwrap()
                        .insert("agent_message".into(), json!(agent));
                }
                print_json(&obj);
            }
            Permission::Deny => {
                let mut obj = json!({
                    "permission": "deny",
                    "user_message": user_message.unwrap_or("Offsend blocked this operation."),
                });
                // Only emit agent_message when the caller provides one (e.g. sealed
                // copy path). Plain denies must not advertise a substitute path.
                if let Some(agent) = agent_message {
                    obj.as_object_mut()
                        .unwrap()
                        .insert("agent_message".into(), json!(agent));
                }
                print_json(&obj);
            }
        }
        Adapter::Claude => match permission {
            Permission::Allow => print_json(&json!({})),
            Permission::Ask | Permission::Deny => {
                let decision = match permission {
                    Permission::Ask => "ask",
                    _ => "deny",
                };
                let reason = user_message.unwrap_or("Offsend blocked this operation.");
                let full = match agent_message {
                    Some(a) => format!("{reason} {a}"),
                    None => reason.to_string(),
                };
                print_json(&json!({
                    "hookSpecificOutput": {
                        "hookEventName": "PreToolUse",
                        "permissionDecision": decision,
                        "permissionDecisionReason": full,
                    }
                }));
            }
        },
        Adapter::Windsurf | Adapter::Codex => {}
    }
    ExitCode::SUCCESS
}

pub fn empty_ok() -> ExitCode {
    print_json(&json!({}));
    ExitCode::SUCCESS
}

pub fn fail_open(adapter: Adapter, reason: &str, kind: GateKind) -> ExitCode {
    let _ = writeln!(
        io::stderr(),
        "offsend: fail-open ({}): {reason}",
        adapter.as_str()
    );
    match kind {
        GateKind::Prompt => prompt_allow(adapter),
        GateKind::Permission => permission_response(adapter, Permission::Allow, None, None),
        GateKind::Observe => empty_ok(),
    }
}

#[derive(Clone, Copy)]
#[allow(dead_code)]
pub enum GateKind {
    Prompt,
    Permission,
    Observe,
}
