//! `--write-gate`

use super::artifacts::{self, Enforcement};
use super::render::{self, Permission};
use super::sensitive;
use super::Adapter;
use serde_json::Value;
use std::process::ExitCode;

pub fn run(adapter: Adapter, stdin: &str) -> ExitCode {
    if !matches!(
        adapter,
        Adapter::Cursor | Adapter::Claude | Adapter::Windsurf
    ) {
        return render::permission_response(adapter, Permission::Allow, None, None);
    }
    if stdin.trim().is_empty() {
        // Cursor remote sometimes sends empty — ask/deny.
        return finish(
            adapter,
            Permission::Ask,
            "Offsend: empty write-gate payload — confirm this write manually.",
        );
    }
    if stdin.len() > crate::io::MAX_INPUT_BYTES {
        return finish(
            adapter,
            Permission::Ask,
            "Offsend: write-gate input exceeds safety limit — confirm manually.",
        );
    }
    let root: Value = match serde_json::from_str(stdin) {
        Ok(v) => v,
        Err(_) => {
            return finish(
                adapter,
                Permission::Ask,
                "Offsend: unrecognized write-gate input — confirm manually.",
            )
        }
    };
    let cwd = root
        .get("cwd")
        .and_then(|v| v.as_str())
        .or_else(|| root.pointer("/tool_info/cwd").and_then(|v| v.as_str()));
    let paths = extract_paths(&root);
    let content = extract_content(&root);
    let edit = extract_edit(&root);

    let mut strongest = Permission::Allow;
    let mut reason = String::new();

    for raw in &paths {
        let path = sensitive::resolve_path(raw, cwd);
        let Some(artifact) = artifacts::classify(&path) else {
            continue;
        };
        match artifact.enforcement {
            Enforcement::Deny => {
                strongest = Permission::Deny;
                reason = format!(
                    "Offsend blocked writing executable workspace configuration ({}). Review and edit this trust surface manually.",
                    std::path::Path::new(&path)
                        .file_name()
                        .and_then(|s| s.to_str())
                        .unwrap_or("file")
                );
            }
            Enforcement::DenyWhenContentExecutable => {
                let deny = match (&content, &edit) {
                    // Full Write: judge the payload body.
                    (Some(c), None) => Some(artifacts::content_looks_executable(c)),
                    // In-place Edit: judge which setting key the old_string sits under.
                    (_, Some((old, _new))) => {
                        match std::fs::read_to_string(&path)
                            .ok()
                            .filter(|s| s.len() <= 1024 * 1024)
                        {
                            Some(file) => {
                                Some(artifacts::edit_touches_executable_setting(&file, old))
                            }
                            None => content
                                .as_ref()
                                .map(|c| artifacts::content_looks_executable(c)),
                        }
                    }
                    (None, None) => match std::fs::read_to_string(&path)
                        .ok()
                        .filter(|s| s.len() <= 1024 * 1024)
                    {
                        Some(file) => Some(artifacts::content_looks_executable(&file)),
                        None => None,
                    },
                };
                match deny {
                    Some(true) => {
                        strongest = Permission::Deny;
                        reason = format!(
                            "Offsend blocked writing editor configuration ({}) that carries interpreter/shell/task commands.",
                            std::path::Path::new(&path)
                                .file_name()
                                .and_then(|s| s.to_str())
                                .unwrap_or("file")
                        );
                    }
                    Some(false) => {}
                    None => {
                        if strongest == Permission::Allow {
                            strongest = Permission::Ask;
                            reason = format!(
                                "Offsend: writing editor configuration ({}) that can carry interpreter paths — confirm.",
                                std::path::Path::new(&path)
                                    .file_name()
                                    .and_then(|s| s.to_str())
                                    .unwrap_or("file")
                            );
                        }
                    }
                }
            }
            Enforcement::Observe => {}
        }
        if strongest == Permission::Deny {
            break;
        }
    }

    match strongest {
        Permission::Allow => render::permission_response(adapter, Permission::Allow, None, None),
        other => finish(adapter, other, &reason),
    }
}

/// Cursor/Windsurf cannot surface `ask` — map it to deny.
fn finish(adapter: Adapter, permission: Permission, reason: &str) -> ExitCode {
    let effective = match (adapter, permission) {
        (Adapter::Cursor | Adapter::Windsurf, Permission::Ask) => Permission::Deny,
        (_, other) => other,
    };
    match effective {
        Permission::Allow => render::permission_response(adapter, Permission::Allow, None, None),
        other => render::permission_response(adapter, other, Some(reason), Some(reason)),
    }
}

fn extract_paths(root: &Value) -> Vec<String> {
    let mut out = Vec::new();
    let tool = root
        .get("tool_input")
        .or_else(|| root.get("toolInput"))
        .or_else(|| root.get("tool_info"));
    let sources = [tool, Some(root)];
    const KEYS: &[&str] = &[
        "file_path",
        "filePath",
        "path",
        "target_file",
        "notebook_path",
        "notebookPath",
    ];
    for src in sources.into_iter().flatten() {
        for key in KEYS {
            if let Some(p) = src.get(*key).and_then(|v| v.as_str()) {
                if !p.is_empty() {
                    out.push(p.to_string());
                }
            }
        }
        for arr_key in ["paths", "target_paths", "targetPaths"] {
            if let Some(arr) = src.get(arr_key).and_then(|v| v.as_array()) {
                for item in arr {
                    if let Some(p) = item.as_str() {
                        out.push(p.to_string());
                    }
                }
            }
        }
    }
    out
}

fn extract_content(root: &Value) -> Option<String> {
    let tool = root
        .get("tool_input")
        .or_else(|| root.get("toolInput"))
        .or_else(|| root.get("tool_info"));
    for src in [tool, Some(root)].into_iter().flatten() {
        if let Some(c) = src.get("content").and_then(|v| v.as_str()) {
            return Some(c.to_string());
        }
        if let Some(edits) = src.get("edits").and_then(|v| v.as_array()) {
            let mut buf = String::new();
            for edit in edits {
                if let Some(s) = edit.get("new_string").and_then(|v| v.as_str()) {
                    buf.push_str(s);
                    buf.push('\n');
                }
            }
            if !buf.is_empty() {
                return Some(buf);
            }
        }
        // Bare new_string without old_string is still content; Edit pairs go
        // through extract_edit so the on-disk key context can be reconstructed.
        if src.get("old_string").and_then(|v| v.as_str()).is_none() {
            if let Some(c) = src.get("new_string").and_then(|v| v.as_str()) {
                return Some(c.to_string());
            }
        }
    }
    None
}

fn extract_edit(root: &Value) -> Option<(String, String)> {
    let tool = root
        .get("tool_input")
        .or_else(|| root.get("toolInput"))
        .or_else(|| root.get("tool_info"));
    for src in [tool, Some(root)].into_iter().flatten() {
        let old = src.get("old_string").and_then(|v| v.as_str());
        let new = src.get("new_string").and_then(|v| v.as_str());
        if let (Some(old), Some(new)) = (old, new) {
            return Some((old.to_string(), new.to_string()));
        }
        if let Some(edits) = src.get("edits").and_then(|v| v.as_array()) {
            if let Some(edit) = edits.first() {
                let old = edit.get("old_string").and_then(|v| v.as_str());
                let new = edit.get("new_string").and_then(|v| v.as_str());
                if let (Some(old), Some(new)) = (old, new) {
                    return Some((old.to_string(), new.to_string()));
                }
            }
        }
    }
    None
}
