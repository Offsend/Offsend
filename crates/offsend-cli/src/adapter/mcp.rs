//! `--mcp-gate` and `--mcp-response-gate`

use super::render::{self, Permission};
use super::sensitive::{self, is_suspicious};
use super::Adapter;
use offsend_detect::DetectionEngine;
use serde_json::{json, Value};
use std::io::{self, Write};
use std::process::ExitCode;

#[derive(Clone, Copy, PartialEq, Eq)]
enum McpMode {
    Observe,
    Ask,
    Deny,
}

pub fn run_call(
    adapter: Adapter,
    secrets_only: bool,
    stdin: &str,
    mode_raw: Option<&str>,
    allow_servers: &[String],
    deny_servers: &[String],
) -> ExitCode {
    if !matches!(
        adapter,
        Adapter::Cursor | Adapter::Claude | Adapter::Windsurf
    ) {
        return render::permission_response(adapter, Permission::Allow, None, None);
    }
    let mode = match mode_raw.unwrap_or("ask") {
        "observe" => McpMode::Observe,
        "deny" => McpMode::Deny,
        _ => McpMode::Ask,
    };

    if stdin.len() > crate::io::MAX_INPUT_BYTES {
        return if mode == McpMode::Deny {
            render::permission_response(
                adapter,
                Permission::Deny,
                Some("Offsend: MCP hook input exceeds safety limit."),
                None,
            )
        } else {
            render::fail_open(adapter, "stdin_too_large", render::GateKind::Permission)
        };
    }
    let root: Value = match serde_json::from_str(stdin) {
        Ok(v) => v,
        Err(_) => {
            return if mode == McpMode::Deny {
                render::permission_response(
                    adapter,
                    Permission::Deny,
                    Some("Offsend: unrecognized MCP hook input denied."),
                    None,
                )
            } else {
                render::fail_open(adapter, "invalid_json", render::GateKind::Permission)
            }
        }
    };

    let cwd = root
        .get("cwd")
        .and_then(|v| v.as_str())
        .or_else(|| root.pointer("/tool_info/cwd").and_then(|v| v.as_str()))
        .or_else(|| {
            root.get("workspace_roots")
                .and_then(|v| v.as_array())
                .and_then(|a| a.first())
                .and_then(|v| v.as_str())
        });
    let server = root
        .get("server")
        .or_else(|| root.get("server_name"))
        .or_else(|| root.get("serverName"))
        .or_else(|| root.pointer("/tool_info/mcp_server_name"))
        .and_then(|v| v.as_str())
        .unwrap_or("");
    let tool_input = root
        .get("tool_input")
        .or_else(|| root.get("toolInput"))
        .or_else(|| root.pointer("/tool_info/mcp_tool_arguments"))
        .cloned()
        .unwrap_or(Value::Null);
    let serialized = tool_input.to_string();

    let mut finding: Option<String> = None;

    if let Some(reason) = server_policy_finding(server, allow_servers, deny_servers) {
        finding = Some(reason);
    }

    // Path tokens in args
    for candidate in path_like_strings(&tool_input) {
        let path = sensitive::resolve_path(&candidate, cwd);
        if sensitive::sensitivity_check_paths(&path, cwd)
            .iter()
            .any(|p| is_suspicious(p))
        {
            finding = Some(format!(
                "Offsend: MCP call references sensitive path ({}).",
                std::path::Path::new(&path)
                    .file_name()
                    .and_then(|s| s.to_str())
                    .unwrap_or("path")
            ));
            break;
        }
    }

    if finding.is_none() {
        let scan = DetectionEngine::scan_including_encoded(&serialized);
        if scan.budget_exceeded {
            finding = Some(
                "Offsend: MCP call arguments contain encoded content exceeding the safe decode budget."
                    .into(),
            );
        } else {
            let secrets: Vec<_> = scan
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
            if !secrets.is_empty() {
                finding = Some(format!(
                    "Offsend: MCP call arguments contain {} sensitive finding(s).",
                    secrets.len()
                ));
            }
        }
    }

    let Some(reason) = finding else {
        return render::permission_response(adapter, Permission::Allow, None, None);
    };

    match mode {
        McpMode::Observe => {
            let _ = writeln!(io::stderr(), "offsend: mcp-gate: {reason}");
            render::permission_response(adapter, Permission::Allow, None, None)
        }
        McpMode::Ask => {
            render::permission_response(adapter, Permission::Ask, Some(&reason), Some(&reason))
        }
        McpMode::Deny => {
            render::permission_response(adapter, Permission::Deny, Some(&reason), Some(&reason))
        }
    }
}

pub fn run_response(
    adapter: Adapter,
    secrets_only: bool,
    stdin: &str,
    mode_raw: Option<&str>,
) -> ExitCode {
    if !matches!(
        adapter,
        Adapter::Cursor | Adapter::Claude | Adapter::Windsurf
    ) {
        return render::empty_ok();
    }
    let mode = mode_raw.unwrap_or("observe"); // observe | warn | seal
    if stdin.len() > crate::io::MAX_INPUT_BYTES {
        // Withhold rather than allow plaintext.
        return withhold(adapter, "MCP response exceeds safety limit.");
    }
    let root: Value = match serde_json::from_str(stdin) {
        Ok(v) => v,
        Err(_) => return render::empty_ok(),
    };

    let (body, can_replace) = extract_response_body(&root, adapter);
    // Decode base64/hex blobs so an MCP server cannot return an encoded secret
    // that slips past the gate. Exceeding the decode budget withholds output.
    let scan = DetectionEngine::scan_including_encoded(&body);
    if scan.budget_exceeded {
        return withhold(
            adapter,
            "MCP response has encoded content exceeding the safe decode budget.",
        );
    }
    let secrets: Vec<_> = scan
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
        return render::empty_ok();
    }

    let n = secrets.len();
    match mode {
        "warn" => {
            let msg = format!("Offsend: MCP response contains {n} sensitive finding(s).");
            match adapter {
                Adapter::Cursor => {
                    render::print_json(&json!({"additional_context": msg}));
                }
                Adapter::Claude => {
                    render::print_json(&json!({
                        "hookSpecificOutput": {
                            "additionalContext": msg
                        }
                    }));
                }
                // Windsurf cannot inject context into MCP output; surface on stderr.
                Adapter::Windsurf => {
                    let _ = writeln!(io::stderr(), "offsend: mcp-response: {msg}");
                }
                _ => {}
            }
            ExitCode::SUCCESS
        }
        "seal" if can_replace => match try_seal_body(&body, &secrets) {
            Ok(sealed) => {
                let msg = format!(
                    "Offsend sealed {} secret value(s) in MCP output.",
                    secrets.len()
                );
                match adapter {
                    Adapter::Cursor => {
                        render::print_json(&json!({
                            "updated_mcp_tool_output": sealed,
                            "additional_context": msg,
                        }));
                    }
                    Adapter::Claude => {
                        render::print_json(&json!({
                            "hookSpecificOutput": {
                                "updatedToolOutput": sealed,
                                "updatedMCPToolOutput": sealed,
                                "additionalContext": msg,
                            }
                        }));
                    }
                    // Windsurf has no replace API — fall back to withhold via exit 2.
                    Adapter::Windsurf => {
                        return withhold(adapter, &msg);
                    }
                    _ => {}
                }
                ExitCode::SUCCESS
            }
            Err(e) => withhold(adapter, &e),
        },
        "seal" => {
            let _ = writeln!(
                io::stderr(),
                "offsend: mcp-response: {} sensitive finding(s) (cannot replace output)",
                secrets.len()
            );
            render::empty_ok()
        }
        _ => {
            let _ = writeln!(
                io::stderr(),
                "offsend: mcp-response: {n} secrets found in tool output (observe only)"
            );
            render::empty_ok()
        }
    }
}

fn try_seal_body(body: &str, secrets: &[offsend_detect::SensitiveEntity]) -> Result<Value, String> {
    let key = crate::keys::resolve(None, None, std::path::Path::new(".")).map_err(|_| {
        "Offsend withheld MCP output: no seal key. Run `offsend keygen --default`.".to_string()
    })?;
    let engine = offsend_seal::SealEngine::new(&key).map_err(|e| e.to_string())?;
    let mut spans: Vec<offsend_seal::SealSpan> = secrets
        .iter()
        .map(|e| offsend_seal::SealSpan {
            start: e.start,
            end: e.end,
            value: e.value.clone(),
            type_label: e.entity_type.placeholder_prefix().to_string(),
        })
        .collect();
    spans.sort_by_key(|s| s.start);
    let sealed = engine
        .seal_spans(body, &spans)
        .map_err(|e| format!("seal failed: {e}"))?;
    Ok(json!(sealed.sealed_text))
}

fn withhold(adapter: Adapter, message: &str) -> ExitCode {
    match adapter {
        Adapter::Cursor => {
            render::print_json(&json!({
                "updated_mcp_tool_output": {"error": message},
                "additional_context": message,
            }));
            ExitCode::SUCCESS
        }
        Adapter::Claude => {
            let withheld = json!({"error": message});
            render::print_json(&json!({
                "hookSpecificOutput": {
                    "updatedToolOutput": withheld,
                    "updatedMCPToolOutput": withheld,
                    "additionalContext": message,
                }
            }));
            ExitCode::SUCCESS
        }
        // Post-hooks cannot block; still fail closed on stderr so operators notice.
        Adapter::Windsurf => {
            let _ = writeln!(io::stderr(), "offsend: mcp-response withheld: {message}");
            ExitCode::SUCCESS
        }
        _ => ExitCode::SUCCESS,
    }
}

fn extract_response_body(root: &Value, adapter: Adapter) -> (String, bool) {
    match adapter {
        Adapter::Cursor => {
            if let Some(v) = root.get("tool_output").or_else(|| root.get("toolOutput")) {
                return (value_as_text(v), true);
            }
            if let Some(v) = root.get("result_json").or_else(|| root.get("resultJson")) {
                return (value_as_text(v), false);
            }
            (String::new(), false)
        }
        Adapter::Claude => {
            if let Some(v) = root
                .get("tool_response")
                .or_else(|| root.get("toolResponse"))
            {
                return (value_as_text(v), true);
            }
            (String::new(), false)
        }
        Adapter::Windsurf => {
            if let Some(v) = root.pointer("/tool_info/mcp_result") {
                // Windsurf post-hooks cannot rewrite MCP output.
                return (value_as_text(v), false);
            }
            (String::new(), false)
        }
        _ => (String::new(), false),
    }
}

fn value_as_text(v: &Value) -> String {
    match v {
        Value::String(s) => s.clone(),
        other => other.to_string(),
    }
}

fn server_policy_finding(
    server: &str,
    allow: &[String],
    deny: &[String],
) -> Option<String> {
    if server.is_empty() {
        return None;
    }
    let matches = |patterns: &[String]| {
        patterns
            .iter()
            .any(|p| p == "*" || p.eq_ignore_ascii_case(server))
    };
    if matches(deny) {
        // `deny: ["*"]` with a non-empty allow list is allowlist mode.
        if deny.iter().any(|d| d == "*") && !allow.is_empty() {
            if !matches(allow) {
                return Some(format!(
                    "Offsend: MCP server `{server}` is not on context.mcp.allow."
                ));
            }
        } else {
            return Some(format!(
                "Offsend: MCP server `{server}` is denied by context.mcp.deny."
            ));
        }
    } else if !allow.is_empty() && !matches(allow) {
        return Some(format!(
            "Offsend: MCP server `{server}` is not on context.mcp.allow."
        ));
    }
    None
}

fn path_like_strings(value: &Value) -> Vec<String> {
    let mut out = Vec::new();
    walk(value, &mut out);
    out
}

fn walk(value: &Value, out: &mut Vec<String>) {
    match value {
        Value::String(s) => {
            if s.contains('/') || s.contains('\\') || s.starts_with('.') {
                out.push(s.clone());
            }
        }
        Value::Array(arr) => {
            for v in arr {
                walk(v, out);
            }
        }
        Value::Object(map) => {
            for v in map.values() {
                walk(v, out);
            }
        }
        _ => {}
    }
}
