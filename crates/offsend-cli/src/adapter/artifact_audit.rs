//! `--artifact-audit` provenance ledger (JSONL).

use super::artifacts;
use super::sensitive;
use super::Adapter;
use serde_json::{json, Value};
use sha2::{Digest, Sha256};
use std::fs::{self, OpenOptions};
use std::io::Write;
use std::path::{Path, PathBuf};
use std::process::ExitCode;
use std::time::{SystemTime, UNIX_EPOCH};

pub fn run(adapter: Adapter, stdin: &str) -> ExitCode {
    let Ok(root) = serde_json::from_str::<Value>(stdin) else {
        return ExitCode::SUCCESS;
    };
    let cwd = root.get("cwd").and_then(|v| v.as_str());
    let paths = extract_paths(&root);
    let repo = cwd
        .map(PathBuf::from)
        .or_else(|| std::env::current_dir().ok())
        .unwrap_or_else(|| PathBuf::from("."));

    for raw in paths {
        let path = sensitive::resolve_path(&raw, cwd);
        let Some(artifact) = artifacts::classify(&path) else {
            continue;
        };
        let _ = record(&repo, &path, artifact.kind, adapter);
    }
    ExitCode::SUCCESS
}

fn extract_paths(root: &Value) -> Vec<String> {
    let mut out = Vec::new();
    let tool = root
        .get("tool_input")
        .or_else(|| root.get("toolInput"))
        .or_else(|| root.get("tool_info"));
    for src in [tool, Some(root)].into_iter().flatten() {
        for key in ["file_path", "filePath", "path", "target_file"] {
            if let Some(p) = src.get(key).and_then(|v| v.as_str()) {
                out.push(p.to_string());
            }
        }
    }
    out
}

fn ledger_path() -> PathBuf {
    #[cfg(target_os = "macos")]
    {
        crate::keys::home_dir()
            .join("Library/Application Support/Offsend/artifact-provenance.jsonl")
    }
    #[cfg(not(target_os = "macos"))]
    {
        std::env::var_os("XDG_CONFIG_HOME")
            .map(PathBuf::from)
            .unwrap_or_else(|| crate::keys::home_dir().join(".config"))
            .join("offsend/artifact-provenance.jsonl")
    }
}

fn hex_encode(bytes: &[u8]) -> String {
    bytes.iter().map(|b| format!("{b:02x}")).collect()
}

fn sha256_hex(data: &[u8]) -> String {
    let mut h = Sha256::new();
    h.update(data);
    hex_encode(&h.finalize())
}

fn record(repo: &Path, absolute: &str, kind: &str, adapter: Adapter) -> std::io::Result<()> {
    let log = ledger_path();
    if let Some(parent) = log.parent() {
        fs::create_dir_all(parent)?;
    }
    let rel = relative_or_external(repo, absolute, kind);
    let content_hash = std::fs::read(absolute)
        .ok()
        .filter(|b| b.len() <= 2 * 1024 * 1024)
        .map(|b| sha256_hex(&b));
    let previous = fs::read_to_string(&log)
        .ok()
        .and_then(|s| s.lines().last().map(|l| sha256_hex(l.as_bytes())));
    let ts = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs();
    let entry = json!({
        "timestamp": ts.to_string(),
        "repositoryID": sha256_hex(repo.display().to_string().as_bytes()),
        "relativePath": rel,
        "pathHash": sha256_hex(absolute.as_bytes()),
        "artifactKind": kind,
        "adapter": adapter.as_str(),
        "toolName": "afterFileEdit",
        "outcome": "changed",
        "contentHash": content_hash,
        "previousHash": previous,
    });
    let line = serde_json::to_string(&entry).unwrap_or_else(|_| "{}".into());
    let mut file = OpenOptions::new().create(true).append(true).open(&log)?;
    writeln!(file, "{line}")?;
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        let _ = fs::set_permissions(&log, fs::Permissions::from_mode(0o600));
    }
    // Rotate if huge
    if let Ok(meta) = fs::metadata(&log) {
        if meta.len() > 512 * 1024 {
            let rotated = log.with_extension("jsonl.1");
            let _ = fs::rename(&log, rotated);
        }
    }
    Ok(())
}

fn relative_or_external(repo: &Path, absolute: &str, kind: &str) -> String {
    let abs = Path::new(absolute);
    if let Ok(rel) = abs.strip_prefix(repo) {
        return rel.to_string_lossy().replace('\\', "/");
    }
    let name = abs.file_name().and_then(|s| s.to_str()).unwrap_or("file");
    format!("<external>/{kind}/{name}")
}
