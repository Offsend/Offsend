//! Seal key paths and resolution — port of Swift `SealKeyPaths` / `SealKeyResolver`.

use base64::engine::general_purpose::STANDARD;
use base64::Engine as _;
use rand::RngCore;
use std::fs;
use std::path::{Path, PathBuf};
use thiserror::Error;

pub const KEY_BYTE_COUNT: usize = 32;
pub const ENV_VAR: &str = "OFFSEND_SEAL_KEY";
pub const DEFAULT_INSTALL_HINT: &str = "offsend keygen --default";

#[derive(Debug, Error)]
pub enum KeyError {
    #[error("Invalid seal key: {0}")]
    Invalid(String),
}

pub fn generate() -> [u8; KEY_BYTE_COUNT] {
    let mut key = [0u8; KEY_BYTE_COUNT];
    rand::thread_rng().fill_bytes(&mut key);
    key
}

pub fn home_dir() -> PathBuf {
    if let Ok(home) = std::env::var("HOME") {
        if !home.is_empty() {
            return PathBuf::from(home);
        }
    }
    dirs_fallback()
}

fn dirs_fallback() -> PathBuf {
    // Minimal fallback without extra deps.
    PathBuf::from(".")
}

pub fn offsend_home() -> PathBuf {
    home_dir().join(".offsend")
}

pub fn default_key_path() -> PathBuf {
    offsend_home().join("seal.key")
}

pub fn named_key_path(name: &str) -> Result<PathBuf, KeyError> {
    let name = validate_key_name(name)?;
    Ok(offsend_home().join("keys").join(format!("{name}.key")))
}

pub fn validate_key_name(name: &str) -> Result<String, KeyError> {
    let trimmed = name.trim();
    if trimmed.is_empty() {
        return Err(KeyError::Invalid("key name must not be empty".into()));
    }
    if trimmed.len() > 64
        || !trimmed
            .chars()
            .all(|c| c.is_ascii_alphanumeric() || matches!(c, '.' | '_' | '-'))
    {
        return Err(KeyError::Invalid(
            "key name must be 1–64 characters: letters, digits, '.', '_', or '-'".into(),
        ));
    }
    if trimmed == "." || trimmed == ".." || trimmed.starts_with('.') {
        return Err(KeyError::Invalid(
            "key name must not be '.' / '..' or start with '.'".into(),
        ));
    }
    Ok(trimmed.to_string())
}

/// Priority: key_file > key_name > OFFSEND_SEAL_KEY > ~/.offsend/seal.key
pub fn resolve(
    key_file: Option<&str>,
    key_name: Option<&str>,
    cwd: &Path,
) -> Result<Vec<u8>, KeyError> {
    let provided = [key_file.is_some(), key_name.is_some()]
        .into_iter()
        .filter(|x| *x)
        .count();
    if provided > 1 {
        return Err(KeyError::Invalid(
            "pass only one of --key-file or --key-name".into(),
        ));
    }

    if let Some(path) = key_file {
        let path = if Path::new(path).is_absolute() {
            PathBuf::from(path)
        } else {
            cwd.join(path)
        };
        return load_key_file(&path);
    }

    if let Some(name) = key_name {
        return load_key_file(&named_key_path(name)?);
    }

    if let Ok(env) = std::env::var(ENV_VAR) {
        if !env.is_empty() {
            return decode_base64_key(&env);
        }
    }

    let default = default_key_path();
    if default.is_file() {
        return load_key_file(&default);
    }

    Err(KeyError::Invalid(format!(
        "provide --key-file or --key-name, set {ENV_VAR}, or run: {DEFAULT_INSTALL_HINT}"
    )))
}

pub fn decode_base64_key(string: &str) -> Result<Vec<u8>, KeyError> {
    let trimmed = string.trim();
    let data = STANDARD
        .decode(trimmed.as_bytes())
        .map_err(|_| KeyError::Invalid("value is not valid base64".into()))?;
    if data.len() != KEY_BYTE_COUNT {
        return Err(KeyError::Invalid(format!(
            "expected 32 bytes after base64 decode, got {}",
            data.len()
        )));
    }
    Ok(data)
}

pub fn load_key_file(path: &Path) -> Result<Vec<u8>, KeyError> {
    let data = fs::read(path)
        .map_err(|_| KeyError::Invalid(format!("could not read key file at {}", path.display())))?;
    if data.len() == KEY_BYTE_COUNT {
        return Ok(data);
    }
    if let Ok(as_string) = String::from_utf8(data.clone()) {
        if let Ok(decoded) = decode_base64_key(&as_string) {
            return Ok(decoded);
        }
    }
    Err(KeyError::Invalid(
        "key file must be 32 raw bytes or base64 encoding of 32 bytes".into(),
    ))
}

pub fn write_key(key: &[u8], path: &Path, raw: bool, force: bool) -> Result<(), KeyError> {
    if key.len() != KEY_BYTE_COUNT {
        return Err(KeyError::Invalid("expected 32-byte seal key".into()));
    }
    if path
        .symlink_metadata()
        .map(|m| m.file_type().is_symlink())
        .unwrap_or(false)
    {
        return Err(KeyError::Invalid(format!(
            "refusing to write seal key through symlink at {}",
            path.display()
        )));
    }
    if path.exists() && !force {
        return Err(KeyError::Invalid(format!(
            "seal key already exists at {}; use --force to overwrite, or --name for a separate key",
            path.display()
        )));
    }
    if let Some(parent) = path.parent() {
        ensure_dir(parent)?;
    }
    let payload = if raw {
        key.to_vec()
    } else {
        format!("{}\n", STANDARD.encode(key)).into_bytes()
    };
    let tmp = path.with_extension(format!("tmp-{}", std::process::id()));
    let _ = fs::remove_file(&tmp); // clear any stale temp from a crashed run
    write_key_bytes(&tmp, &payload)?;
    fs::rename(&tmp, path).map_err(|e| {
        let _ = fs::remove_file(&tmp);
        KeyError::Invalid(e.to_string())
    })?;
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        let _ = fs::set_permissions(path, fs::Permissions::from_mode(0o600));
    }
    Ok(())
}

/// Write key material to a fresh file created with 0600 from the start, so the
/// bytes never exist on disk with default (umask, often 0644) permissions.
fn write_key_bytes(path: &Path, payload: &[u8]) -> Result<(), KeyError> {
    #[cfg(unix)]
    {
        use std::io::Write;
        use std::os::unix::fs::OpenOptionsExt;
        let mut f = fs::OpenOptions::new()
            .write(true)
            .create_new(true)
            .mode(0o600)
            .open(path)
            .map_err(|e| KeyError::Invalid(e.to_string()))?;
        f.write_all(payload)
            .map_err(|e| KeyError::Invalid(e.to_string()))
    }
    #[cfg(not(unix))]
    {
        fs::write(path, payload).map_err(|e| KeyError::Invalid(e.to_string()))
    }
}

fn ensure_dir(path: &Path) -> Result<(), KeyError> {
    if path.is_dir() {
        #[cfg(unix)]
        if is_managed(path) {
            use std::os::unix::fs::PermissionsExt;
            let _ = fs::set_permissions(path, fs::Permissions::from_mode(0o700));
        }
        return Ok(());
    }
    fs::create_dir_all(path).map_err(|e| KeyError::Invalid(e.to_string()))?;
    #[cfg(unix)]
    if is_managed(path) {
        use std::os::unix::fs::PermissionsExt;
        let _ = fs::set_permissions(path, fs::Permissions::from_mode(0o700));
    }
    Ok(())
}

fn is_managed(path: &Path) -> bool {
    let root = offsend_home();
    path.starts_with(&root)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[cfg(unix)]
    #[test]
    fn key_file_is_created_private() {
        use std::os::unix::fs::PermissionsExt;
        let dir = std::env::temp_dir().join(format!("offsend-keys-test-{}", std::process::id()));
        let _ = fs::create_dir_all(&dir);
        let path = dir.join("k.bin");
        let _ = fs::remove_file(&path);
        write_key_bytes(&path, b"0123456789abcdef0123456789abcdef").unwrap();
        let mode = fs::metadata(&path).unwrap().permissions().mode() & 0o777;
        assert_eq!(mode, 0o600, "key must never touch disk with loose permissions");
        let _ = fs::remove_file(&path);
        let _ = fs::remove_dir(&dir);
    }
}
