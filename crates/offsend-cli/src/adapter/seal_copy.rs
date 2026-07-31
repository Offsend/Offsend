//! Seal prompt findings to a private temp file + clipboard (Swift `SealCopyStore` / CheckHookEmitter).

use offsend_detect::SensitiveEntity;
use offsend_seal::{SealEngine, SealSpan};
use std::fs;
use std::io::Write;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::time::{SystemTime, UNIX_EPOCH};

pub struct SealCopyOutcome {
    pub ok: bool,
    pub path: Option<PathBuf>,
    pub message_suffix: String,
}

/// Seal `entities` in `text`, write 0600 temp file, best-effort pbcopy on Darwin.
pub fn attempt(
    text: &str,
    entities: &[SensitiveEntity],
    key: &[u8],
) -> SealCopyOutcome {
    let spans: Vec<SealSpan> = entities
        .iter()
        .map(|e| SealSpan {
            start: e.start,
            end: e.end,
            value: e.value.clone(),
            type_label: e.entity_type.placeholder_prefix().to_string(),
        })
        .collect();

    let engine = match SealEngine::new(key) {
        Ok(e) => e,
        Err(_) => {
            return SealCopyOutcome {
                ok: false,
                path: None,
                message_suffix: " Seal unavailable — install a key with `offsend keygen --default`."
                    .into(),
            };
        }
    };

    let sealed = match engine.seal_spans(text, &spans) {
        Ok(r) => r.sealed_text,
        Err(_) => {
            return SealCopyOutcome {
                ok: false,
                path: None,
                message_suffix: " Seal unavailable — could not seal findings.".into(),
            };
        }
    };

    cleanup_old_files();
    let path = match write_temp(&sealed) {
        Ok(p) => p,
        Err(_) => {
            return SealCopyOutcome {
                ok: false,
                path: None,
                message_suffix: " Seal unavailable — could not write temp file.".into(),
            };
        }
    };

    let _ = copy_clipboard(&sealed);

    SealCopyOutcome {
        ok: true,
        path: Some(path),
        message_suffix: " A sealed copy is on the clipboard (and in a private temp file)."
            .into(),
    }
}

fn directory() -> PathBuf {
    std::env::temp_dir().join("offsend-seal")
}

fn write_temp(contents: &str) -> Result<PathBuf, String> {
    let dir = directory();
    fs::create_dir_all(&dir).map_err(|e| e.to_string())?;
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        let _ = fs::set_permissions(&dir, fs::Permissions::from_mode(0o700));
    }
    let nanos = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_nanos())
        .unwrap_or(0);
    let path = dir.join(format!("sealed-{nanos}.txt"));
    fs::write(&path, contents).map_err(|e| e.to_string())?;
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        let _ = fs::set_permissions(&path, fs::Permissions::from_mode(0o600));
    }
    Ok(path)
}

fn cleanup_old_files() {
    let dir = directory();
    let Ok(entries) = fs::read_dir(&dir) else {
        return;
    };
    let cutoff = SystemTime::now()
        .checked_sub(std::time::Duration::from_secs(3600))
        .unwrap_or(UNIX_EPOCH);
    for entry in entries.flatten() {
        let path = entry.path();
        let Ok(meta) = entry.metadata() else { continue };
        let Ok(modified) = meta.modified() else { continue };
        if modified < cutoff {
            let _ = fs::remove_file(path);
        }
    }
}

fn copy_clipboard(text: &str) -> bool {
    #[cfg(target_os = "macos")]
    {
        let mut child = match Command::new("/usr/bin/pbcopy")
            .stdin(Stdio::piped())
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .spawn()
        {
            Ok(c) => c,
            Err(_) => return false,
        };
        if let Some(mut stdin) = child.stdin.take() {
            if stdin.write_all(text.as_bytes()).is_err() {
                return false;
            }
        }
        child.wait().map(|s| s.success()).unwrap_or(false)
    }
    #[cfg(not(target_os = "macos"))]
    {
        let _ = text;
        false
    }
}

#[allow(dead_code)]
pub fn temp_dir_path() -> PathBuf {
    directory()
}

#[allow(dead_code)]
pub fn is_under_seal_dir(path: &Path) -> bool {
    path.starts_with(directory())
}
