//! Policy trust snapshots — port of Swift `OffsendPolicySnapshotStore`.
//!
//! Snapshot covers `.offsend.yml` and, when present, the project provider file
//! `.offsend/sandbox.<name>.yml` selected by `sandbox.provider`.

use sha2::{Digest, Sha256};
use std::fs;
use std::path::{Path, PathBuf};
use std::time::{SystemTime, UNIX_EPOCH};

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum TrustStatus {
    Missing,
    Trusted,
    Drift(String),
    Invalid(String),
}

#[derive(serde::Serialize, serde::Deserialize)]
struct Snapshot {
    version: u32,
    repository_path: String,
    config_hash: String,
    /// Hash of project `sandbox.<provider>.yml` when present at trust time.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    provider_hash: Option<String>,
    /// Provider id that `provider_hash` refers to (for drift messages).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    provider_id: Option<String>,
    trusted_at: String,
}

const SNAPSHOT_VERSION: u32 = 2;

fn hex_encode(bytes: &[u8]) -> String {
    bytes.iter().map(|b| format!("{b:02x}")).collect()
}

pub fn store_dir() -> PathBuf {
    #[cfg(target_os = "macos")]
    {
        crate::keys::home_dir().join("Library/Application Support/Offsend/policy-snapshots")
    }
    #[cfg(not(target_os = "macos"))]
    {
        std::env::var_os("XDG_CONFIG_HOME")
            .map(PathBuf::from)
            .unwrap_or_else(|| crate::keys::home_dir().join(".config"))
            .join("offsend/policy-snapshots")
    }
}

fn snapshot_path(repo_root: &Path) -> PathBuf {
    let mut hasher = Sha256::new();
    hasher.update(repo_root.display().to_string().as_bytes());
    store_dir().join(format!("{}.json", hex_encode(&hasher.finalize())))
}

fn config_hash(bytes: &[u8]) -> String {
    let mut hasher = Sha256::new();
    hasher.update(bytes);
    hex_encode(&hasher.finalize())
}

/// Provider id declared in `.offsend.yml`, or catalog default.
pub fn declared_provider_id(repo_root: &Path) -> Option<String> {
    let path = repo_root.join(".offsend.yml");
    let text = fs::read_to_string(path).ok()?;
    let value: serde_yaml::Value = serde_yaml::from_str(&text).ok()?;
    let sandbox = value.get("sandbox")?;
    match sandbox.get("provider") {
        Some(serde_yaml::Value::String(s)) => {
            let id = s.trim();
            if id.is_empty() {
                None
            } else {
                Some(id.to_string())
            }
        }
        Some(serde_yaml::Value::Mapping(map)) => {
            let key = serde_yaml::Value::String("name".into());
            map.get(&key)
                .and_then(|v| v.as_str())
                .map(|s| s.trim().to_string())
                .filter(|s| !s.is_empty())
                .or_else(|| crate::sandbox_provider::default_provider_id().ok())
        }
        None => crate::sandbox_provider::default_provider_id().ok(),
        _ => None,
    }
}

fn project_provider_hash(repo_root: &Path) -> (Option<String>, Option<String>) {
    let Some(id) = declared_provider_id(repo_root) else {
        return (None, None);
    };
    let path = crate::sandbox_provider::project_provider_path(repo_root, &id);
    if !path.is_file() {
        return (Some(id), None);
    }
    match fs::read(&path) {
        Ok(bytes) => (Some(id), Some(config_hash(&bytes))),
        Err(_) => (Some(id), None),
    }
}

pub fn is_trusted(repo_root: &Path) -> bool {
    matches!(status(repo_root), TrustStatus::Trusted)
}

pub fn status(repo_root: &Path) -> TrustStatus {
    let path = snapshot_path(repo_root);
    if !path.is_file() {
        return TrustStatus::Missing;
    }
    let Ok(raw) = fs::read_to_string(&path) else {
        return TrustStatus::Invalid("unreadable trust snapshot".into());
    };
    let Ok(snap) = serde_json::from_str::<Snapshot>(&raw) else {
        return TrustStatus::Invalid("malformed trust snapshot".into());
    };
    if snap.version != 1 && snap.version != SNAPSHOT_VERSION {
        return TrustStatus::Invalid(format!("unsupported snapshot version {}", snap.version));
    }
    let config_path = repo_root.join(".offsend.yml");
    let Ok(bytes) = fs::read(&config_path) else {
        return TrustStatus::Drift("trusted .offsend.yml is missing or unreadable".into());
    };
    let hash = config_hash(&bytes);
    if hash != snap.config_hash {
        return TrustStatus::Drift(
            "workspace .offsend.yml no longer matches the trusted snapshot".into(),
        );
    }

    let (provider_id, provider_hash) = project_provider_hash(repo_root);
    if snap.version >= SNAPSHOT_VERSION {
        if provider_hash != snap.provider_hash {
            let id = provider_id
                .or(snap.provider_id)
                .unwrap_or_else(|| "unknown".into());
            return TrustStatus::Drift(format!(
                "project sandbox provider file for `{id}` no longer matches the trusted snapshot \
                 (or was added/removed). Run: offsend policy trust"
            ));
        }
    } else if provider_hash.is_some() {
        // v1 snapshot + new project provider file → force re-trust.
        return TrustStatus::Drift(
            "project sandbox.<name>.yml is present but the trust snapshot predates provider hashing. \
             Run: offsend policy trust"
                .into(),
        );
    }

    TrustStatus::Trusted
}

pub fn trust(repo_root: &Path) -> Result<PathBuf, String> {
    let config_path = repo_root.join(".offsend.yml");
    let bytes = fs::read(&config_path).map_err(|_| {
        format!(
            "No .offsend.yml at {}. Run `offsend init` first.",
            repo_root.display()
        )
    })?;
    let dir = store_dir();
    fs::create_dir_all(&dir).map_err(|e| e.to_string())?;
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        let _ = fs::set_permissions(&dir, fs::Permissions::from_mode(0o700));
    }
    let now = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs();
    let (provider_id, provider_hash) = project_provider_hash(repo_root);
    let snap = Snapshot {
        version: SNAPSHOT_VERSION,
        repository_path: repo_root.display().to_string(),
        config_hash: config_hash(&bytes),
        provider_hash,
        provider_id,
        trusted_at: format!("{now}"),
    };
    let path = snapshot_path(repo_root);
    let text = serde_json::to_string_pretty(&snap).map_err(|e| e.to_string())?;
    fs::write(&path, text + "\n").map_err(|e| e.to_string())?;
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        let _ = fs::set_permissions(&path, fs::Permissions::from_mode(0o600));
    }
    Ok(path)
}

pub fn forget(repo_root: &Path) -> Result<bool, String> {
    let path = snapshot_path(repo_root);
    if !path.is_file() {
        return Ok(false);
    }
    fs::remove_file(&path).map_err(|e| e.to_string())?;
    Ok(true)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::time::{SystemTime, UNIX_EPOCH};

    #[test]
    fn trust_then_drift_on_change() {
        let nanos = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        let dir = std::env::temp_dir().join(format!("offsend-trust-{nanos}"));
        fs::create_dir_all(dir.join(".git")).unwrap();
        fs::write(dir.join(".offsend.yml"), "version: 1\n").unwrap();
        trust(&dir).unwrap();
        assert_eq!(status(&dir), TrustStatus::Trusted);
        fs::write(
            dir.join(".offsend.yml"),
            "version: 1\ncheck:\n  fail_on: none\n",
        )
        .unwrap();
        assert!(matches!(status(&dir), TrustStatus::Drift(_)));
        forget(&dir).unwrap();
        assert_eq!(status(&dir), TrustStatus::Missing);
        let _ = fs::remove_dir_all(dir);
    }

    #[test]
    fn trust_drifts_when_project_provider_added() {
        let nanos = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        let dir = std::env::temp_dir().join(format!("offsend-trust-prov-{nanos}"));
        fs::create_dir_all(dir.join(".git")).unwrap();
        fs::write(
            dir.join(".offsend.yml"),
            "version: 1\nsandbox:\n  enabled: true\n  provider: nono\n",
        )
        .unwrap();
        trust(&dir).unwrap();
        assert_eq!(status(&dir), TrustStatus::Trusted);
        fs::create_dir_all(dir.join(".offsend")).unwrap();
        fs::write(
            dir.join(".offsend/sandbox.nono.yml"),
            "name: nono\nbinary: /bin/echo\nprofile_directory: .offsend/nono\nrun_args: []\n",
        )
        .unwrap();
        assert!(matches!(status(&dir), TrustStatus::Drift(_)));
        forget(&dir).unwrap();
        let _ = fs::remove_dir_all(dir);
    }

    #[test]
    fn trust_drifts_when_project_provider_modified() {
        let nanos = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        let dir = std::env::temp_dir().join(format!("offsend-trust-mod-{nanos}"));
        fs::create_dir_all(dir.join(".offsend")).unwrap();
        fs::create_dir_all(dir.join(".git")).unwrap();
        fs::write(
            dir.join(".offsend.yml"),
            "version: 1\nsandbox:\n  enabled: true\n  provider: custom\n",
        )
        .unwrap();
        fs::write(
            dir.join(".offsend/sandbox.custom.yml"),
            "name: custom\nbinary: /usr/bin/true\nprofile_directory: .offsend/c\nrun_args: []\n",
        )
        .unwrap();
        trust(&dir).unwrap();
        assert_eq!(status(&dir), TrustStatus::Trusted);
        fs::write(
            dir.join(".offsend/sandbox.custom.yml"),
            "name: custom\nbinary: /bin/echo\nprofile_directory: .offsend/c\nrun_args: []\n",
        )
        .unwrap();
        let st = status(&dir);
        assert!(matches!(st, TrustStatus::Drift(_)), "{st:?}");
        forget(&dir).unwrap();
        let _ = fs::remove_dir_all(dir);
    }

    #[test]
    fn trust_drifts_when_project_provider_removed() {
        let nanos = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        let dir = std::env::temp_dir().join(format!("offsend-trust-rm-{nanos}"));
        fs::create_dir_all(dir.join(".offsend")).unwrap();
        fs::create_dir_all(dir.join(".git")).unwrap();
        fs::write(
            dir.join(".offsend.yml"),
            "version: 1\nsandbox:\n  enabled: true\n  provider: custom\n",
        )
        .unwrap();
        let prov = dir.join(".offsend/sandbox.custom.yml");
        fs::write(
            &prov,
            "name: custom\nbinary: /usr/bin/true\nprofile_directory: .offsend/c\nrun_args: []\n",
        )
        .unwrap();
        trust(&dir).unwrap();
        fs::remove_file(&prov).unwrap();
        assert!(matches!(status(&dir), TrustStatus::Drift(_)));
        forget(&dir).unwrap();
        let _ = fs::remove_dir_all(dir);
    }

    #[test]
    fn v1_snapshot_drifts_when_project_provider_appears() {
        let nanos = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        let dir = std::env::temp_dir().join(format!("offsend-trust-v1-{nanos}"));
        fs::create_dir_all(dir.join(".git")).unwrap();
        let config = "version: 1\nsandbox:\n  enabled: true\n  provider: nono\n";
        fs::write(dir.join(".offsend.yml"), config).unwrap();
        // Synthesize a legacy v1 snapshot (config hash only).
        let bytes = fs::read(dir.join(".offsend.yml")).unwrap();
        let mut hasher = Sha256::new();
        hasher.update(&bytes);
        let config_hash = hex_encode(&hasher.finalize());
        let snap = serde_json::json!({
            "version": 1,
            "repository_path": dir.display().to_string(),
            "config_hash": config_hash,
            "trusted_at": "1",
        });
        let path = snapshot_path(&dir);
        fs::create_dir_all(path.parent().unwrap()).unwrap();
        fs::write(&path, snap.to_string() + "\n").unwrap();
        assert_eq!(status(&dir), TrustStatus::Trusted);

        fs::create_dir_all(dir.join(".offsend")).unwrap();
        fs::write(
            dir.join(".offsend/sandbox.nono.yml"),
            "name: nono\nbinary: /bin/echo\nprofile_directory: .offsend/nono\nrun_args: []\n",
        )
        .unwrap();
        let st = status(&dir);
        assert!(
            matches!(&st, TrustStatus::Drift(msg) if msg.contains("predates provider hashing")),
            "{st:?}"
        );
        forget(&dir).unwrap();
        let _ = fs::remove_dir_all(dir);
    }

    #[test]
    fn declared_provider_id_from_string_and_map() {
        let nanos = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        let dir = std::env::temp_dir().join(format!("offsend-trust-id-{nanos}"));
        fs::create_dir_all(&dir).unwrap();
        fs::write(
            dir.join(".offsend.yml"),
            "version: 1\nsandbox:\n  provider: acme\n",
        )
        .unwrap();
        assert_eq!(declared_provider_id(&dir).as_deref(), Some("acme"));
        fs::write(
            dir.join(".offsend.yml"),
            "version: 1\nsandbox:\n  provider:\n    name: other\n    ensure: check\n",
        )
        .unwrap();
        assert_eq!(declared_provider_id(&dir).as_deref(), Some("other"));
        let _ = fs::remove_dir_all(dir);
    }
}
