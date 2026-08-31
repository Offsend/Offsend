//! Shared I/O helpers (Swift `SealIO` subset).

use std::fs;
use std::io::{self, IsTerminal, Read, Write};
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use thiserror::Error;

pub const MAX_INPUT_BYTES: usize = 2 * 1024 * 1024;

#[derive(Debug, Error)]
pub enum IoError {
    #[error("{path} exceeds {max} bytes.")]
    InputTooLarge { path: String, max: usize },
    #[error("{path} is not valid UTF-8.")]
    InvalidUtf8 { path: String },
    #[error("Output already exists at {path}. Use --force to replace it.")]
    OutputExists { path: String },
    #[error("Provide a file path or pipe text on stdin.")]
    StdinTty,
    #[error(
        "Clipboard is empty. Copy the agent's sealed text, then run `offsend unseal` again — or pass a file / pipe stdin."
    )]
    ClipboardEmpty,
    #[error("{0}")]
    ClipboardUnavailable(String),
    #[error("{0}")]
    Message(String),
}

pub fn read_input(path: Option<&str>, working_directory: &Path) -> Result<String, IoError> {
    if let Some(path) = path {
        let url = resolve_path(path, working_directory);
        let data = read_capped(&url, MAX_INPUT_BYTES)?;
        String::from_utf8(data).map_err(|_| IoError::InvalidUtf8 {
            path: url.display().to_string(),
        })
    } else {
        let stdin = io::stdin();
        if stdin.is_terminal() {
            return Err(IoError::StdinTty);
        }
        let mut buf = Vec::new();
        stdin
            .lock()
            .take((MAX_INPUT_BYTES as u64) + 1)
            .read_to_end(&mut buf)
            .map_err(|e| IoError::Message(e.to_string()))?;
        if buf.len() > MAX_INPUT_BYTES {
            return Err(IoError::InputTooLarge {
                path: "stdin".into(),
                max: MAX_INPUT_BYTES,
            });
        }
        String::from_utf8(buf).map_err(|_| IoError::InvalidUtf8 {
            path: "stdin".into(),
        })
    }
}

/// `unseal` input: file, piped stdin, or (TTY, no path) the system clipboard.
///
/// Clipboard is `pbpaste` on macOS and `wl-paste` / `xclip` / `xsel` on Linux.
/// No AppKit. Piped stdin still wins over the clipboard.
pub fn read_unseal_input(path: Option<&str>, working_directory: &Path) -> Result<String, IoError> {
    if path.is_some() {
        return read_input(path, working_directory);
    }
    if !io::stdin().is_terminal() {
        return read_input(None, working_directory);
    }
    let text = read_clipboard()?;
    if text.trim().is_empty() {
        return Err(IoError::ClipboardEmpty);
    }
    Ok(text)
}

pub fn read_clipboard() -> Result<String, IoError> {
    let (program, args) = clipboard_paste_command().ok_or_else(|| {
        IoError::ClipboardUnavailable(
            "Clipboard unavailable (need pbpaste, wl-paste, xclip, or xsel). Pass a file or pipe stdin."
                .into(),
        )
    })?;
    let mut child = Command::new(program)
        .args(args)
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .spawn()
        .map_err(|e| {
            IoError::ClipboardUnavailable(format!("Could not read clipboard ({program}): {e}"))
        })?;
    let mut buf = Vec::new();
    if let Some(stdout) = child.stdout.as_mut() {
        stdout
            .take((MAX_INPUT_BYTES as u64) + 1)
            .read_to_end(&mut buf)
            .map_err(|e| IoError::Message(e.to_string()))?;
    }
    let status = child.wait().map_err(|e| IoError::Message(e.to_string()))?;
    if !status.success() {
        return Err(IoError::ClipboardUnavailable(format!(
            "Clipboard command {program} exited {}",
            status
        )));
    }
    if buf.len() > MAX_INPUT_BYTES {
        return Err(IoError::InputTooLarge {
            path: "clipboard".into(),
            max: MAX_INPUT_BYTES,
        });
    }
    String::from_utf8(buf).map_err(|_| IoError::InvalidUtf8 {
        path: "clipboard".into(),
    })
}

fn clipboard_paste_command() -> Option<(&'static str, &'static [&'static str])> {
    #[cfg(target_os = "macos")]
    {
        Some(("/usr/bin/pbpaste", &[]))
    }
    #[cfg(target_os = "linux")]
    {
        const CANDIDATES: &[(&str, &[&str])] = &[
            ("wl-paste", &[]),
            ("xclip", &["-selection", "clipboard", "-o"]),
            ("xsel", &["--clipboard", "--output"]),
        ];
        CANDIDATES
            .iter()
            .copied()
            .find(|(program, _)| program_on_path(program))
    }
    #[cfg(not(any(target_os = "macos", target_os = "linux")))]
    {
        None
    }
}

#[cfg(target_os = "linux")]
fn program_on_path(program: &str) -> bool {
    Command::new("/bin/sh")
        .arg("-c")
        .arg(format!("command -v {program} >/dev/null 2>&1"))
        .status()
        .map(|s| s.success())
        .unwrap_or(false)
}

pub fn write_output(
    text: &str,
    output: Option<&str>,
    working_directory: &Path,
    force: bool,
) -> Result<(), IoError> {
    if let Some(output) = output {
        let path = resolve_path(output, working_directory);
        write_file_atomically(text.as_bytes(), &path, force)?;
        return Ok(());
    }
    let mut out = io::stdout().lock();
    out.write_all(text.as_bytes())
        .map_err(|e| IoError::Message(e.to_string()))?;
    Ok(())
}

pub fn resolve_path(path: &str, working_directory: &Path) -> PathBuf {
    let p = Path::new(path);
    if p.is_absolute() {
        p.to_path_buf()
    } else {
        working_directory.join(p)
    }
}

pub fn working_dir(explicit: Option<&str>) -> PathBuf {
    explicit
        .map(PathBuf::from)
        .unwrap_or_else(|| std::env::current_dir().unwrap_or_else(|_| PathBuf::from(".")))
}

fn read_capped(path: &Path, max: usize) -> Result<Vec<u8>, IoError> {
    let mut file = fs::File::open(path)
        .map_err(|e| IoError::Message(format!("Failed to read {}: {e}", path.display())))?;
    let mut data = Vec::new();
    let mut chunk = [0u8; 64 * 1024];
    loop {
        let n = file
            .read(&mut chunk)
            .map_err(|e| IoError::Message(e.to_string()))?;
        if n == 0 {
            break;
        }
        if data.len() + n > max {
            return Err(IoError::InputTooLarge {
                path: path.display().to_string(),
                max,
            });
        }
        data.extend_from_slice(&chunk[..n]);
    }
    Ok(data)
}

fn write_file_atomically(data: &[u8], path: &Path, force: bool) -> Result<(), IoError> {
    if path.exists() && !force {
        return Err(IoError::OutputExists {
            path: path.display().to_string(),
        });
    }
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent).map_err(|e| IoError::Message(e.to_string()))?;
    }
    let tmp = path.with_file_name(format!(
        ".{}.offsend-{}.tmp",
        path.file_name().and_then(|s| s.to_str()).unwrap_or("out"),
        std::process::id()
    ));
    fs::write(&tmp, data).map_err(|e| IoError::Message(e.to_string()))?;
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        let _ = fs::set_permissions(&tmp, fs::Permissions::from_mode(0o600));
    }
    fs::rename(&tmp, path).map_err(|e| {
        let _ = fs::remove_file(&tmp);
        IoError::Message(format!(
            "Could not replace output at {}: {e}",
            path.display()
        ))
    })?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Write;
    use std::process::{Command, Stdio};

    #[cfg(target_os = "macos")]
    #[test]
    fn clipboard_roundtrip() {
        let marker = format!("offsend-unseal-test-{}", std::process::id());
        let mut child = Command::new("/usr/bin/pbcopy")
            .stdin(Stdio::piped())
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .spawn()
            .expect("pbcopy");
        child
            .stdin
            .take()
            .unwrap()
            .write_all(marker.as_bytes())
            .unwrap();
        assert!(child.wait().unwrap().success());
        assert_eq!(read_clipboard().unwrap(), marker);
    }

    #[test]
    fn clipboard_empty_message_mentions_unseal() {
        let msg = IoError::ClipboardEmpty.to_string();
        assert!(msg.contains("offsend unseal"));
        assert!(msg.contains("Copy the agent's sealed text"));
    }
}
