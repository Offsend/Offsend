//! `--mcp-gate` and `--mcp-response-gate`

use super::render::{self, Permission};
use super::sensitive::{self, is_suspicious};
use super::Adapter;
use offsend_detect::DetectionEngine;
use serde_json::Value;
use std::io::{self, Write};
use std::path::Path;
use std::process::ExitCode;

const MAX_JSON_DEPTH: usize = 32;

#[derive(Clone, Copy, PartialEq, Eq)]
enum McpMode {
    Observe,
    Ask,
    Deny,
}

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
enum ResponseMode {
    Observe,
    Warn,
    Seal,
}

impl ResponseMode {
    fn parse(raw: Option<&str>) -> Result<Self, String> {
        match raw.unwrap_or("seal") {
            "seal" => Ok(Self::Seal),
            "warn" => Ok(Self::Warn),
            "observe" => Ok(Self::Observe),
            other => Err(format!(
                "unknown context.mcp.responses value `{other}` (expected seal, warn, or observe)"
            )),
        }
    }
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

pub struct ResponseFlags<'a> {
    pub key_file: Option<&'a str>,
    pub key_name: Option<&'a str>,
    pub project_root: &'a Path,
}

pub fn run_response(
    adapter: Adapter,
    secrets_only: bool,
    stdin: &str,
    mode_raw: Option<&str>,
    flags: ResponseFlags<'_>,
) -> ExitCode {
    if !matches!(
        adapter,
        Adapter::Cursor | Adapter::Claude | Adapter::Windsurf
    ) {
        return render::empty_ok();
    }
    let mode = match ResponseMode::parse(mode_raw) {
        Ok(m) => m,
        Err(err) => {
            let _ = writeln!(io::stderr(), "offsend: mcp-response: {err}; using seal");
            ResponseMode::Seal
        }
    };
    if stdin.len() > crate::io::MAX_INPUT_BYTES || stdin.contains('\0') {
        return render::post_tool_withhold(adapter, "MCP response exceeds safety limit.");
    }
    let root: Value = match serde_json::from_str(stdin) {
        Ok(v) => v,
        Err(_) => {
            return render::post_tool_withhold(
                adapter,
                "Offsend withheld MCP output: unrecognized hook input.",
            )
        }
    };

    let (body, can_replace) = match extract_response_body(&root, adapter) {
        Ok(extracted) => extracted,
        Err(reason) => return render::post_tool_withhold(adapter, &reason),
    };
    let scan = match scan_value(&body, secrets_only, 0) {
        Ok(s) => s,
        Err(reason) => return render::post_tool_withhold(adapter, &reason),
    };

    if scan.count == 0 {
        return render::empty_ok();
    }

    let n = scan.count;
    match mode {
        ResponseMode::Warn => {
            let msg = format!("Offsend: MCP response contains {n} sensitive finding(s).");
            render::post_tool_warn(adapter, &msg)
        }
        ResponseMode::Seal if can_replace => match seal_value(
            &body,
            secrets_only,
            flags.key_file,
            flags.key_name,
            flags.project_root,
        ) {
            Ok(sealed) => {
                let msg = format!("Offsend sealed {n} secret value(s) in MCP output.");
                render::post_tool_replace(adapter, sealed, &msg)
            }
            Err(e) => render::post_tool_withhold(adapter, &e),
        },
        ResponseMode::Seal => render::post_tool_withhold(
            adapter,
            "Offsend withheld MCP output: this editor event cannot replace tool output.",
        ),
        ResponseMode::Observe => {
            let _ = writeln!(
                io::stderr(),
                "offsend: mcp-response: {n} secrets found in tool output (observe only)"
            );
            render::empty_ok()
        }
    }
}

struct ScanSummary {
    count: usize,
}

fn scan_value(value: &Value, secrets_only: bool, depth: usize) -> Result<ScanSummary, String> {
    if depth > MAX_JSON_DEPTH {
        return Err("MCP response exceeds the safe JSON depth limit.".into());
    }
    match value {
        Value::String(s) => {
            let scan = DetectionEngine::scan_including_encoded(s);
            if scan.budget_exceeded {
                return Err(
                    "MCP response has encoded content exceeding the safe decode budget.".into(),
                );
            }
            let count = scan
                .entities
                .iter()
                .filter(|e| {
                    if secrets_only {
                        e.entity_type.counts_as_critical_secret()
                    } else {
                        true
                    }
                })
                .count();
            Ok(ScanSummary { count })
        }
        Value::Array(items) => {
            let mut count = 0;
            for item in items {
                count += scan_value(item, secrets_only, depth + 1)?.count;
            }
            Ok(ScanSummary { count })
        }
        Value::Object(map) => {
            let mut count = 0;
            for (key, item) in map {
                if key_has_secret(key, secrets_only)? {
                    return Err(
                        "Offsend withheld MCP output: a JSON key contains a secret and cannot be replaced safely."
                            .into(),
                    );
                }
                count += scan_value(item, secrets_only, depth + 1)?.count;
            }
            Ok(ScanSummary { count })
        }
        _ => Ok(ScanSummary { count: 0 }),
    }
}

fn key_has_secret(key: &str, secrets_only: bool) -> Result<bool, String> {
    let scan = DetectionEngine::scan_including_encoded(key);
    if scan.budget_exceeded {
        return Err("MCP response has encoded content exceeding the safe decode budget.".into());
    }
    Ok(scan.entities.iter().any(|e| {
        if secrets_only {
            e.entity_type.counts_as_critical_secret()
        } else {
            true
        }
    }))
}

fn seal_value(
    value: &Value,
    secrets_only: bool,
    key_file: Option<&str>,
    key_name: Option<&str>,
    project_root: &Path,
) -> Result<Value, String> {
    let key = crate::keys::resolve(key_file, key_name, project_root).map_err(|_| {
        "Offsend withheld MCP output: no seal key. Run `offsend keygen --default`.".to_string()
    })?;
    let engine = offsend_seal::SealEngine::new(&key).map_err(|e| e.to_string())?;
    seal_value_with(&engine, value, secrets_only, 0)
}

fn seal_value_with(
    engine: &offsend_seal::SealEngine,
    value: &Value,
    secrets_only: bool,
    depth: usize,
) -> Result<Value, String> {
    if depth > MAX_JSON_DEPTH {
        return Err("MCP response exceeds the safe JSON depth limit.".into());
    }
    match value {
        Value::String(s) => Ok(Value::String(seal_string(engine, s, secrets_only)?)),
        Value::Array(items) => {
            let mut out = Vec::with_capacity(items.len());
            for item in items {
                out.push(seal_value_with(engine, item, secrets_only, depth + 1)?);
            }
            Ok(Value::Array(out))
        }
        Value::Object(map) => {
            let mut out = serde_json::Map::new();
            for (k, v) in map {
                if key_has_secret(k, secrets_only)? {
                    return Err(
                        "Offsend withheld MCP output: a JSON key contains a secret and cannot be replaced safely."
                            .into(),
                    );
                }
                out.insert(
                    k.clone(),
                    seal_value_with(engine, v, secrets_only, depth + 1)?,
                );
            }
            Ok(Value::Object(out))
        }
        other => Ok(other.clone()),
    }
}

fn seal_string(
    engine: &offsend_seal::SealEngine,
    text: &str,
    secrets_only: bool,
) -> Result<String, String> {
    let scan = DetectionEngine::scan_including_encoded(text);
    if scan.budget_exceeded {
        return Err("MCP response has encoded content exceeding the safe decode budget.".into());
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
        return Ok(text.to_string());
    }
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
        .seal_spans(text, &spans)
        .map_err(|e| format!("seal failed: {e}"))?;
    Ok(sealed.sealed_text)
}

fn extract_response_body(root: &Value, adapter: Adapter) -> Result<(Value, bool), String> {
    match adapter {
        Adapter::Cursor => {
            if let Some(v) = root.get("tool_output").or_else(|| root.get("toolOutput")) {
                return Ok((decode_cursor_tool_output(v)?, true));
            }
            if let Some(v) = root.get("result_json").or_else(|| root.get("resultJson")) {
                return Ok((v.clone(), false));
            }
            Err(
                "Offsend withheld MCP output: missing tool_output (unsupported hook schema)."
                    .into(),
            )
        }
        Adapter::Claude => {
            if let Some(v) = root
                .get("tool_response")
                .or_else(|| root.get("toolResponse"))
            {
                return Ok((v.clone(), true));
            }
            Err(
                "Offsend withheld MCP output: missing tool_response (unsupported hook schema)."
                    .into(),
            )
        }
        Adapter::Windsurf => {
            if let Some(v) = root.pointer("/tool_info/mcp_result") {
                return Ok((v.clone(), false));
            }
            Err(
                "Offsend withheld MCP output: missing tool_info.mcp_result (unsupported hook schema)."
                    .into(),
            )
        }
        _ => Err("Offsend withheld MCP output: unsupported adapter.".into()),
    }
}

/// Cursor sends `tool_output` as a JSON-encoded string. Decode it before
/// scanning so Unicode escapes and object shape match the documented contract.
fn decode_cursor_tool_output(value: &Value) -> Result<Value, String> {
    match value {
        Value::String(raw) => serde_json::from_str(raw).map_err(|_| {
            "Offsend withheld MCP output: tool_output is not valid JSON.".to_string()
        }),
        other => Ok(other.clone()),
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

#[cfg(test)]
mod tests {
    use super::*;
    use crate::keys;
    use serde_json::json;
    use std::fs;
    use std::time::{SystemTime, UNIX_EPOCH};

    fn temp_dir() -> std::path::PathBuf {
        let nanos = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        let dir = std::env::temp_dir().join(format!("offsend-mcp-{nanos}"));
        fs::create_dir_all(&dir).unwrap();
        dir
    }

    fn write_key(dir: &Path) -> std::path::PathBuf {
        let path = dir.join("seal.key");
        keys::write_key(&keys::generate(), &path, true, true).unwrap();
        path
    }

    fn flags<'a>(key: &'a Path, root: &'a Path) -> ResponseFlags<'a> {
        ResponseFlags {
            key_file: Some(key.to_str().unwrap()),
            key_name: None,
            project_root: root,
        }
    }

    fn capture_json(adapter: Adapter, stdin: &str, mode: &str, flags: ResponseFlags<'_>) -> Value {
        // evaluate via run_response is stdout-coupled; use internals for assertions.
        let root: Value = serde_json::from_str(stdin).unwrap();
        let (body, can_replace) = extract_response_body(&root, adapter).unwrap();
        let scan = scan_value(&body, false, 0).unwrap();
        assert!(scan.count > 0, "expected secrets");
        assert!(can_replace || mode != "seal-replace");
        match mode {
            "seal" => seal_value(&body, false, flags.key_file, flags.key_name, flags.project_root)
                .unwrap(),
            _ => body,
        }
    }

    #[test]
    fn object_body_keeps_shape_and_both_secrets() {
        let dir = temp_dir();
        let key = write_key(&dir);
        // offsend:ignore-next-line
        let plain = "DATABASE_URL=postgres://admin:my-real-looking-pass-781492@db.internal/prod\nAWS_ACCESS_KEY_ID=AKIA1234567890ABCDEF";
        let stdin = json!({
            "tool_output": {
                "content": [{ "type": "text", "text": plain }],
                "ok": true,
                "count": 1
            }
        })
        .to_string();
        let sealed = capture_json(Adapter::Cursor, &stdin, "seal", flags(&key, &dir));
        assert!(sealed.is_object(), "{sealed}");
        assert_eq!(sealed.get("ok"), Some(&json!(true)));
        assert_eq!(sealed.get("count"), Some(&json!(1)));
        let text = sealed["content"][0]["text"].as_str().unwrap();
        // offsend:ignore-next-line
        assert!(!text.contains("my-real-looking-pass-781492"), "{text}");
        // offsend:ignore-next-line
        assert!(!text.contains("AKIA1234567890ABCDEF"), "{text}");
        assert!(text.contains("postgres://admin:"), "{text}");
        assert!(text.contains("v1."), "{text}");
        let _ = fs::remove_dir_all(dir);
    }

    #[test]
    fn compact_json_string_keeps_aws_key() {
        let dir = temp_dir();
        let key = write_key(&dir);
        let inner = json!({
            // offsend:ignore-next-line
            "text": "DATABASE_URL=postgres://admin:my-real-looking-pass-781492@db.internal/prod\nAWS_ACCESS_KEY_ID=AKIA1234567890ABCDEF"
        })
        .to_string();
        let sealed = seal_value(
            &Value::String(inner),
            false,
            Some(key.to_str().unwrap()),
            None,
            &dir,
        )
        .unwrap();
        let s = sealed.as_str().unwrap();
        // offsend:ignore-next-line
        assert!(!s.contains("my-real-looking-pass-781492"), "{s}");
        // offsend:ignore-next-line
        assert!(!s.contains("AKIA1234567890ABCDEF"), "{s}");
        let _ = fs::remove_dir_all(dir);
    }

    #[test]
    fn result_json_cannot_replace() {
        // offsend:ignore-next-line
        let root = json!({"result_json": {"secret": "AKIA1234567890ABCDEF"}});
        let (_, can_replace) = extract_response_body(&root, Adapter::Cursor).unwrap();
        assert!(!can_replace);
    }

    #[test]
    fn cursor_transport_string_decodes_to_object() {
        let dir = temp_dir();
        let key = write_key(&dir);
        let inner = json!({
            "content": [{
                "type": "text",
                // offsend:ignore-next-line
                "text": "AWS_ACCESS_KEY_ID=AKIA1234567890ABCDEF"
            }],
            "ok": true
        });
        let root = json!({"tool_output": inner.to_string()});
        let (body, can_replace) = extract_response_body(&root, Adapter::Cursor).unwrap();
        assert!(can_replace);
        assert!(body.is_object(), "{body}");
        assert_eq!(body.get("ok"), Some(&json!(true)));
        let sealed = seal_value(
            &body,
            false,
            Some(key.to_str().unwrap()),
            None,
            &dir,
        )
        .unwrap();
        assert!(sealed.is_object(), "{sealed}");
        assert_eq!(sealed.get("ok"), Some(&json!(true)));
        let text = sealed["content"][0]["text"].as_str().unwrap();
        // offsend:ignore-next-line
        assert!(!text.contains("AKIA1234567890ABCDEF"), "{text}");
        assert!(text.contains("v1."), "{text}");
        let wire = json!({
            "updated_mcp_tool_output": sealed,
            "additional_context": "sealed",
        });
        assert!(
            wire["updated_mcp_tool_output"].is_object(),
            "{wire}"
        );
        let _ = fs::remove_dir_all(dir);
    }

    #[test]
    fn cursor_transport_json_unicode_escape_is_decoded() {
        let dir = temp_dir();
        let key = write_key(&dir);
        let inner = json!({
            "content": [{
                "type": "text",
                // offsend:ignore-next-line
                "text": "AWS_ACCESS_KEY_ID=AKIA1234567890ABCDEF"
            }]
        })
        .to_string()
        .replace("AKIA", r"\u0041KIA");
        let root = json!({"tool_output": inner});
        let (body, can_replace) = extract_response_body(&root, Adapter::Cursor).unwrap();
        assert!(can_replace);
        let text = body["content"][0]["text"].as_str().unwrap();
        assert!(
            // offsend:ignore-next-line
            text.contains("AKIA1234567890ABCDEF"),
            "expected decoded AWS key, got {text}"
        );
        let sealed = seal_value(
            &body,
            false,
            Some(key.to_str().unwrap()),
            None,
            &dir,
        )
        .unwrap();
        assert!(sealed.is_object(), "{sealed}");
        assert!(
            // offsend:ignore-next-line
            !sealed.to_string().contains("AKIA1234567890ABCDEF"),
            "{sealed}"
        );
        let _ = fs::remove_dir_all(dir);
    }

    #[test]
    fn cursor_invalid_inner_json_is_unchecked() {
        let root = json!({"tool_output": "{not-json"});
        let err = extract_response_body(&root, Adapter::Cursor).unwrap_err();
        assert!(err.contains("not valid JSON"), "{err}");
    }

    #[test]
    fn missing_response_field_is_unchecked() {
        // offsend:ignore-next-line
        let root = json!({"result": "AWS_ACCESS_KEY_ID=AKIA1234567890ABCDEF"});
        let err = extract_response_body(&root, Adapter::Claude).unwrap_err();
        assert!(err.contains("missing tool_response"), "{err}");
        let err = extract_response_body(&root, Adapter::Cursor).unwrap_err();
        assert!(err.contains("missing tool_output"), "{err}");
    }

    #[test]
    fn explicit_null_response_is_present_empty() {
        let root = json!({"tool_response": null});
        let (body, can_replace) = extract_response_body(&root, Adapter::Claude).unwrap();
        assert_eq!(body, Value::Null);
        assert!(can_replace);
        assert_eq!(scan_value(&body, false, 0).unwrap().count, 0);
    }

    #[test]
    fn unknown_mode_is_rejected() {
        assert!(ResponseMode::parse(Some("redact")).is_err());
        assert_eq!(ResponseMode::parse(Some("seal")).unwrap(), ResponseMode::Seal);
    }

    #[test]
    fn secret_in_json_key_is_rejected() {
        let dir = temp_dir();
        let key = write_key(&dir);
        // offsend:ignore-next-line
        let value = json!({ "AKIA1234567890ABCDEF": "ok" });
        let err = seal_value(&value, false, Some(key.to_str().unwrap()), None, &dir).unwrap_err();
        assert!(err.contains("JSON key"), "{err}");
        let _ = fs::remove_dir_all(dir);
    }
}
