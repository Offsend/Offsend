//! `--shell-audit` (observational)

use super::render;
use super::Adapter;
use offsend_detect::{DetectionEngine, DetectionRequest, SensitiveEntity};
use serde_json::{json, Value};
use std::fs::{self, OpenOptions};
use std::io::{self, Write};
use std::path::PathBuf;
use std::process::ExitCode;
use std::time::{SystemTime, UNIX_EPOCH};

const MAX_OUTPUT: usize = 256 * 1024;
const MAX_LOG_BYTES: u64 = 256 * 1024;

pub fn run(adapter: Adapter, secrets_only: bool, stdin: &str) -> ExitCode {
    if !matches!(
        adapter,
        Adapter::Cursor | Adapter::Claude | Adapter::Windsurf
    ) {
        return render::empty_ok();
    }
    let root: Value = match serde_json::from_str(stdin) {
        Ok(v) => v,
        Err(_) => return render::empty_ok(),
    };
    let command = root
        .get("command")
        .and_then(|v| v.as_str())
        .or_else(|| root.pointer("/tool_info/command_line").and_then(|v| v.as_str()))
        .unwrap_or("")
        .to_string();
    let sandbox = root
        .get("sandbox")
        .and_then(|v| v.as_bool())
        .unwrap_or(false);
    let output = extract_output(&root, adapter);
    let truncated = output.len() > MAX_OUTPUT;
    let clipped = if truncated {
        // Clip on a UTF-8 char boundary; MAX_OUTPUT may land mid-codepoint
        // (multi-byte output is common) and a raw byte slice would panic.
        let mut cut = MAX_OUTPUT;
        while cut > 0 && !output.is_char_boundary(cut) {
            cut -= 1;
        }
        &output[..cut]
    } else {
        output.as_str()
    };

    // Decode base64/hex blobs too: `secret | base64` in command output must not
    // slip past the audit just because it is encoded.
    let scan = DetectionEngine::scan_including_encoded(clipped);
    if scan.budget_exceeded {
        let _ = writeln!(
            io::stderr(),
            "offsend: shell-audit: encoded content exceeded decode budget; not fully scanned"
        );
    }
    let findings: Vec<&SensitiveEntity> = scan
        .entities
        .iter()
        .filter(|e| {
            if secrets_only {
                e.entity_type.counts_as_critical_secret()
            } else {
                true
            }
        })
        .collect();

    if findings.is_empty() {
        if truncated {
            let _ = writeln!(
                io::stderr(),
                "offsend: shell-audit: command output exceeds {MAX_OUTPUT} bytes; not fully scanned"
            );
        }
        return render::empty_ok();
    }

    let mut types: Vec<&'static str> = findings
        .iter()
        .map(|e| e.entity_type.swift_name())
        .collect();
    types.sort_unstable();
    types.dedup();
    let types_joined = types.join(", ");

    let _ = writeln!(
        io::stderr(),
        "offsend: shell-audit: {types_joined} ({} sensitive finding(s) in command output)",
        findings.len()
    );
    if truncated {
        let _ = writeln!(
            io::stderr(),
            "offsend: shell-audit: command output exceeds {MAX_OUTPUT} bytes; not fully scanned"
        );
    }

    let redacted_command = redact_command(&command, clipped, &findings);
    let _ = append_log(&redacted_command, &types, sandbox);
    render::empty_ok()
}

fn redact_command(command: &str, output: &str, findings: &[&SensitiveEntity]) -> String {
    // Prefer longer values first so nested/overlapping replacements stay stable.
    let mut replacements: Vec<(String, &'static str)> = findings
        .iter()
        .filter_map(|e| {
            if e.end <= output.len() && e.start < e.end {
                Some((
                    output[e.start..e.end].to_string(),
                    e.entity_type.swift_name(),
                ))
            } else {
                None
            }
        })
        .collect();
    // Secrets that appear only in the command line still must not land on disk.
    let cmd_scan = DetectionEngine::scan(&DetectionRequest::new(command.to_string()));
    for e in &cmd_scan.entities {
        if e.entity_type.counts_as_critical_secret() || e.entity_type.is_secret() {
            if e.end <= command.len() && e.start < e.end {
                replacements.push((
                    command[e.start..e.end].to_string(),
                    e.entity_type.swift_name(),
                ));
            }
        }
    }
    replacements.sort_by(|a, b| b.0.len().cmp(&a.0.len()));
    replacements.dedup_by(|a, b| a.0 == b.0);
    let mut redacted = command.to_string();
    for (value, type_name) in replacements {
        if value.is_empty() {
            continue;
        }
        redacted = redacted.replace(&value, &format!("OFFSEND_REDACTED_{type_name}"));
    }
    redacted
}

fn audit_log_path() -> PathBuf {
    #[cfg(target_os = "macos")]
    {
        crate::keys::home_dir().join("Library/Application Support/Offsend/shell-output-audit.log")
    }
    #[cfg(not(target_os = "macos"))]
    {
        std::env::var_os("XDG_CONFIG_HOME")
            .map(PathBuf::from)
            .unwrap_or_else(|| crate::keys::home_dir().join(".config"))
            .join("offsend/shell-output-audit.log")
    }
}

fn append_log(command: &str, types: &[&str], sandbox: bool) -> std::io::Result<()> {
    let log = audit_log_path();
    if let Some(parent) = log.parent() {
        fs::create_dir_all(parent)?;
    }
    let ts = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs();
    let entry = json!({
        "timestamp": ts.to_string(),
        "command": command,
        "types": types,
        "sandbox": sandbox,
    });
    let line = serde_json::to_string(&entry).unwrap_or_else(|_| "{}".into());
    let mut file = OpenOptions::new().create(true).append(true).open(&log)?;
    writeln!(file, "{line}")?;
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        let _ = fs::set_permissions(&log, fs::Permissions::from_mode(0o600));
    }
    if let Ok(meta) = fs::metadata(&log) {
        if meta.len() > MAX_LOG_BYTES {
            let rotated = log.with_extension("log.1");
            let _ = fs::rename(&log, rotated);
        }
    }
    Ok(())
}

fn extract_output(root: &Value, adapter: Adapter) -> String {
    match adapter {
        Adapter::Cursor => root.get("output").map(value_as_text).unwrap_or_default(),
        Adapter::Claude => root
            .get("tool_response")
            .or_else(|| root.get("toolResponse"))
            .map(value_as_text)
            .unwrap_or_default(),
        _ => String::new(),
    }
}

fn value_as_text(v: &Value) -> String {
    match v {
        Value::String(s) => s.clone(),
        other => other.to_string(),
    }
}
