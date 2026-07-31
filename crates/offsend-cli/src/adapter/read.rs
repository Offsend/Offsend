//! `--read-gate`

use super::render::{self, Permission};
use super::seal_copy;
use super::sensitive::{self, is_suspicious};
use super::Adapter;
use offsend_detect::{DetectionEngine, DetectionRequest, SensitiveEntity};
use serde_json::Value;
use std::path::Path;
use std::process::ExitCode;

pub fn run(
    adapter: Adapter,
    secrets_only: bool,
    stdin: &str,
    exclude_patterns: &[String],
    project_root: Option<&std::path::Path>,
    on_secret_seal: bool,
    key_file: Option<&str>,
    key_name: Option<&str>,
) -> ExitCode {
    if !matches!(adapter, Adapter::Cursor | Adapter::Claude) {
        return render::permission_response(adapter, Permission::Allow, None, None);
    }
    if stdin.len() > crate::io::MAX_INPUT_BYTES {
        return deny(
            adapter,
            &format!(
                "Offsend: blocked this read — hook input exceeds the {}-byte safety limit.",
                crate::io::MAX_INPUT_BYTES
            ),
            None,
        );
    }
    let root: Value = match serde_json::from_str(stdin) {
        Ok(v) => v,
        Err(_) => {
            return deny(
                adapter,
                "Offsend: unrecognized read-gate hook input denied.",
                None,
            )
        }
    };
    let cwd = root.get("cwd").and_then(|v| v.as_str());
    let Some(raw_path) = extract_path(&root, adapter) else {
        return deny(
            adapter,
            "Offsend: unrecognized read-gate hook input denied.",
            None,
        );
    };
    let path = sensitive::resolve_path(raw_path, cwd);

    // Sealed copies are intentionally readable by the agent.
    if is_sealed_copy_path(&path) {
        return render::permission_response(adapter, Permission::Allow, None, None);
    }

    if let Some(root) = project_root {
        if is_excluded(&path, cwd, exclude_patterns, root) {
            return render::permission_response(adapter, Permission::Allow, None, None);
        }
    }

    let path_suspicious = sensitive::sensitivity_check_paths(&path, cwd)
        .into_iter()
        .any(|candidate| is_suspicious(&candidate));

    let content = extract_content(&root, adapter).or_else(|| read_disk(&path));
    if let Some(ref content) = content {
        if content.len() > crate::io::MAX_INPUT_BYTES {
            let name = Path::new(&path)
                .file_name()
                .and_then(|s| s.to_str())
                .unwrap_or("file");
            return deny(
                adapter,
                &format!("Offsend: blocked reading {name} — file exceeds scan limit."),
                None,
            );
        }
    }

    // Seal mode ignores detectors.disable — always scan the full detector set.
    let findings: Vec<SensitiveEntity> = if let Some(ref content) = content {
        let result = DetectionEngine::scan(&DetectionRequest::new(content.clone()));
        result
            .entities
            .into_iter()
            .filter(|e| {
                if secrets_only && !on_secret_seal {
                    e.entity_type.counts_as_critical_secret()
                } else if on_secret_seal {
                    true
                } else {
                    e.entity_type.counts_as_critical_secret()
                }
            })
            .collect()
    } else {
        Vec::new()
    };

    if !path_suspicious && findings.is_empty() {
        return render::permission_response(adapter, Permission::Allow, None, None);
    }

    let name = Path::new(&path)
        .file_name()
        .and_then(|s| s.to_str())
        .unwrap_or("file");

    if on_secret_seal {
        if let (Some(content), Some(root)) = (content.as_ref(), project_root) {
            if let Ok(key) = crate::keys::resolve(key_file, key_name, root) {
                let entities = if findings.is_empty() {
                    // Sensitive path with no detector hits: still refuse plaintext.
                    Vec::new()
                } else {
                    findings.clone()
                };
                if !entities.is_empty() {
                    let outcome = seal_copy::attempt(content, &entities, &key);
                    if let Some(sealed_path) = outcome.path {
                        // Keep the sealed path as the last filesystem path in the
                        // message so e2e / agents can extract `…/offsend-seal/sealed-*.txt`.
                        let agent = format!(
                            "Offsend blocked reading {name}; use the sealed copy without plaintext secrets at {}",
                            sealed_path.display()
                        );
                        let user = format!(
                            "Offsend: blocked reading {name} — secrets sealed to a private temp file for the agent."
                        );
                        return deny(adapter, &user, Some(&agent));
                    }
                }
            }
        }
        // No key / seal failed: plain deny (no agent_message) so plaintext is not offered.
        return deny(
            adapter,
            &format!(
                "Offsend: blocked reading sensitive path ({name}) — keep credentials out of agent context. \
                 Use env secrets or `offsend ignore '{name}'`."
            ),
            None,
        );
    }

    if path_suspicious {
        return deny(
            adapter,
            &format!(
                "Offsend: blocked reading sensitive path ({name}) — keep credentials out of agent context. \
                 Use env secrets or `offsend ignore '{name}'`."
            ),
            None,
        );
    }

    let mut types: Vec<_> = findings
        .iter()
        .map(|e| format!("{:?}", e.entity_type))
        .collect();
    types.sort();
    types.dedup();
    deny(
        adapter,
        &format!(
            "Offsend: blocked reading {name} — contains secrets ({}). \
             Keep them out of agent context (env / secret manager), or `offsend ignore` the path.",
            types.join(", ")
        ),
        None,
    )
}

fn deny(adapter: Adapter, reason: &str, agent: Option<&str>) -> ExitCode {
    render::permission_response(adapter, Permission::Deny, Some(reason), agent)
}

fn is_sealed_copy_path(path: &str) -> bool {
    let lower = path.replace('\\', "/").to_ascii_lowercase();
    lower.contains("/offsend-seal/") && lower.contains("/sealed-") && lower.ends_with(".txt")
}

fn extract_path<'a>(root: &'a Value, adapter: Adapter) -> Option<&'a str> {
    match adapter {
        Adapter::Cursor => root
            .get("file_path")
            .or_else(|| root.get("filePath"))
            .or_else(|| root.get("path"))
            .and_then(|v| v.as_str()),
        Adapter::Claude => root
            .pointer("/tool_input/file_path")
            .or_else(|| root.pointer("/tool_input/path"))
            .or_else(|| root.get("file_path"))
            .and_then(|v| v.as_str()),
        _ => None,
    }
}

fn extract_content(root: &Value, adapter: Adapter) -> Option<String> {
    let v = match adapter {
        Adapter::Cursor => root.get("content"),
        Adapter::Claude => root
            .get("content")
            .or_else(|| root.pointer("/tool_input/content")),
        _ => None,
    };
    v.and_then(|v| v.as_str()).map(str::to_string)
}

fn read_disk(path: &str) -> Option<String> {
    let meta = std::fs::metadata(path).ok()?;
    if !meta.is_file() || meta.len() > crate::io::MAX_INPUT_BYTES as u64 {
        return None;
    }
    std::fs::read_to_string(path).ok()
}

fn is_excluded(
    path: &str,
    cwd: Option<&str>,
    patterns: &[String],
    project_root: &std::path::Path,
) -> bool {
    use offsend_policy::PathExcludeMatcher;
    if patterns.is_empty() {
        return false;
    }
    let root = project_root
        .canonicalize()
        .unwrap_or_else(|_| project_root.to_path_buf());
    let root_s = root.to_string_lossy();
    sensitive::sensitivity_check_paths(path, cwd)
        .into_iter()
        .all(|candidate| {
            let cand = std::path::Path::new(&candidate)
                .canonicalize()
                .unwrap_or_else(|_| std::path::PathBuf::from(&candidate));
            let cand_s = cand.to_string_lossy();
            let Some(rel) = cand_s.strip_prefix(root_s.as_ref()) else {
                return false;
            };
            let rel = rel.trim_start_matches('/');
            PathExcludeMatcher::is_excluded(rel, patterns)
        })
}
