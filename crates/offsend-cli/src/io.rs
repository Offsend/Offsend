//! Shared I/O helpers (Swift `SealIO` subset).

use std::fs;
use std::io::{self, IsTerminal, Read, Write};
use std::path::{Path, PathBuf};
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
