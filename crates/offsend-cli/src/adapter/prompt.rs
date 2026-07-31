//! Prompt submit path (`--hook-policy`).

use super::render::{self, GateKind};
use super::seal_copy;
use super::{Adapter, HookPolicy};
use offsend_detect::{DetectionEngine, DetectionRequest, SensitiveEntity};
use serde_json::Value;
use std::io::Write;
use std::path::Path;
use std::process::ExitCode;

pub fn run(
    adapter: Adapter,
    policy: HookPolicy,
    secrets_only: bool,
    seal_copy_flag: bool,
    key_file: Option<&str>,
    key_name: Option<&str>,
    project_root: &Path,
    stdin: &str,
    exclude_patterns: &[String],
) -> ExitCode {
    if stdin.len() > crate::io::MAX_INPUT_BYTES {
        return render::fail_open(adapter, "stdin_too_large", GateKind::Prompt);
    }
    let root: Value = match serde_json::from_str(stdin) {
        Ok(v) => v,
        Err(_) => return render::fail_open(adapter, "invalid_json", GateKind::Prompt),
    };
    let prompt = match extract_prompt(&root, adapter) {
        Some(p) => p,
        None => return render::fail_open(adapter, "missing_prompt", GateKind::Prompt),
    };

    let cwd = root.get("cwd").and_then(|v| v.as_str());
    let mut text = prompt.clone();
    // Best-effort attachment / @mention file contents (bounded).
    for path in attachment_paths(&root)
        .into_iter()
        .chain(at_mention_paths(&prompt, cwd))
    {
        if path_is_excluded(&path, exclude_patterns) {
            continue;
        }
        let resolved = if let Some(cwd) = cwd {
            if std::path::Path::new(&path).is_absolute() {
                path
            } else {
                std::path::Path::new(cwd).join(path).display().to_string()
            }
        } else {
            path
        };
        if let Ok(bytes) = std::fs::read(&resolved) {
            if bytes.len() <= 64 * 1024 {
                if let Ok(s) = String::from_utf8(bytes) {
                    text.push('\n');
                    text.push_str(&s);
                }
            }
        }
    }

    let result = DetectionEngine::scan(&DetectionRequest::new(text));
    let scanned = result.scanned_text.clone();
    let findings: Vec<SensitiveEntity> = result
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

    if findings.is_empty() {
        return render::prompt_allow(adapter);
    }

    let should_seal = seal_copy_flag || matches!(policy, HookPolicy::Block);
    let mut summary = format!(
        "Offsend blocked this prompt: {} sensitive finding(s).",
        findings.len()
    );

    if should_seal {
        match crate::keys::resolve(key_file, key_name, project_root) {
            Ok(key) => {
                let outcome = seal_copy::attempt(&scanned, &findings, &key);
                summary.push_str(&outcome.message_suffix);
            }
            Err(_) => {
                summary.push_str(
                    " Seal unavailable — install a key with `offsend keygen --default` (same as soft-block without a key).",
                );
                let _ = writeln!(
                    std::io::stderr(),
                    "offsend: seal unavailable — run `offsend keygen --default`"
                );
            }
        }
    }

    match policy {
        HookPolicy::Advise => render::prompt_advise(adapter, &summary),
        HookPolicy::SoftBlock | HookPolicy::Block => render::prompt_deny(adapter, &summary),
    }
}

fn extract_prompt(root: &Value, adapter: Adapter) -> Option<String> {
    match adapter {
        Adapter::Cursor | Adapter::Claude | Adapter::Codex => root
            .get("prompt")
            .and_then(|v| v.as_str())
            .map(str::to_string),
        Adapter::Windsurf => root
            .pointer("/tool_info/user_prompt")
            .and_then(|v| v.as_str())
            .map(str::to_string),
    }
}

fn attachment_paths(root: &Value) -> Vec<String> {
    let mut out = Vec::new();
    if let Some(arr) = root.get("attachments").and_then(|v| v.as_array()) {
        for item in arr {
            if let Some(p) = item
                .get("file_path")
                .or_else(|| item.get("filePath"))
                .and_then(|v| v.as_str())
            {
                if !p.is_empty() {
                    out.push(p.to_string());
                }
            }
        }
    }
    out
}

fn path_is_excluded(path: &str, patterns: &[String]) -> bool {
    use offsend_policy::PathExcludeMatcher;
    if patterns.is_empty() {
        return false;
    }
    let normalized: Vec<String> = patterns
        .iter()
        .map(|p| {
            if p.ends_with('/') && !p.ends_with("/**") {
                format!("{}**", p)
            } else {
                p.clone()
            }
        })
        .collect();
    let trimmed = path.trim_start_matches("./");
    PathExcludeMatcher::is_excluded(trimmed, &normalized)
}

/// Cursor/Claude `@path` mentions in the prompt body.
fn at_mention_paths(prompt: &str, _cwd: Option<&str>) -> Vec<String> {
    let mut out = Vec::new();
    let mut rest = prompt;
    while let Some(idx) = rest.find('@') {
        rest = &rest[idx + 1..];
        if rest.is_empty() {
            break;
        }
        // Skip email-like @domain
        let first = rest.chars().next().unwrap();
        if !first.is_ascii_alphanumeric() && first != '.' && first != '/' && first != '_' {
            continue;
        }
        let end = rest
            .find(|c: char| c.is_whitespace() || c == ',' || c == ';' || c == ')' || c == ']')
            .unwrap_or(rest.len());
        let candidate = &rest[..end];
        if candidate.contains('/') || candidate.contains('.') {
            out.push(candidate.to_string());
        }
        rest = &rest[end..];
    }
    out
}
