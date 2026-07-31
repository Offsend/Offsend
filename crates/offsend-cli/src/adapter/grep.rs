//! `--grep-gate` (Cursor)

use super::render::{self, Permission};
use super::sensitive;
use super::Adapter;
use offsend_detect::{DetectionEngine, DetectionRequest};
use serde_json::Value;
use std::process::ExitCode;

pub fn run(adapter: Adapter, secrets_only: bool, stdin: &str, on_secret_seal: bool) -> ExitCode {
    if !matches!(adapter, Adapter::Cursor) {
        return ExitCode::SUCCESS;
    }
    if stdin.len() > crate::io::MAX_INPUT_BYTES {
        return render::permission_response(
            adapter,
            Permission::Deny,
            Some("Offsend: grep-gate input exceeds safety limit."),
            None,
        );
    }
    let root: Value = match serde_json::from_str(stdin) {
        Ok(v) => v,
        Err(_) => {
            return render::permission_response(
                adapter,
                Permission::Deny,
                Some("Offsend: unrecognized grep-gate input denied."),
                None,
            )
        }
    };

    if on_secret_seal {
        return render::permission_response(
            adapter,
            Permission::Deny,
            Some(
                "Offsend blocked Grep: context.read.on_secret is seal, and Cursor cannot rewrite Grep hits. \
                 Search without sensitive files, or change on_secret.",
            ),
            None,
        );
    }

    let cwd = root.get("cwd").and_then(|v| v.as_str());
    let path = extract_file_path(&root, cwd);
    let Some(path) = path else {
        return render::permission_response(adapter, Permission::Allow, None, None);
    };

    let Ok(meta) = std::fs::metadata(&path) else {
        return render::permission_response(adapter, Permission::Allow, None, None);
    };
    if !meta.is_file() || meta.len() > crate::io::MAX_INPUT_BYTES as u64 {
        return render::permission_response(adapter, Permission::Allow, None, None);
    }
    let Ok(content) = std::fs::read_to_string(&path) else {
        return render::permission_response(adapter, Permission::Allow, None, None);
    };
    let result = DetectionEngine::scan(&DetectionRequest::new(content));
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
    let name = std::path::Path::new(&path)
        .file_name()
        .and_then(|s| s.to_str())
        .unwrap_or("file");
    render::permission_response(
        adapter,
        Permission::Deny,
        Some(&format!(
            "Offsend blocked Grep on {name}: contains {} secret finding(s).",
            secrets.len()
        )),
        None,
    )
}

fn extract_file_path(root: &Value, cwd: Option<&str>) -> Option<String> {
    let tool = root.get("tool_input").or_else(|| root.get("toolInput"));
    for src in [tool, Some(root)].into_iter().flatten() {
        for key in ["path", "file_path", "filePath", "file"] {
            if let Some(raw) = src.get(key).and_then(|v| v.as_str()) {
                let resolved = sensitive::resolve_path(raw, cwd);
                if std::path::Path::new(&resolved).is_file() {
                    return Some(resolved);
                }
            }
        }
    }
    None
}
