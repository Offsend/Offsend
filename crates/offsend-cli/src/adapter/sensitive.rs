//! Sensitive path heuristics — port of Swift `PromptAttachmentAdvisor`.

use std::path::Path;

const SENSITIVE_DIRECTORY_COMPONENTS: &[&str] = &[
    ".ssh", ".aws", ".azure", ".kube", ".docker", ".gnupg", ".fly",
];

const SENSITIVE_BASENAMES: &[&str] = &[
    "id_rsa",
    "id_ed25519",
    "id_ecdsa",
    "kubeconfig",
    "serviceaccountkey",
    "secring",
    "accesskeys",
    "firebase-adminsdk",
    "application-local",
];

const SECRET_DOCUMENT_BASENAMES: &[&str] = &["credentials", "secrets"];

const SECRET_DOCUMENT_EXTENSIONS: &[&str] = &[
    "json",
    "yml",
    "yaml",
    "csv",
    "env",
    "toml",
    "ini",
    "conf",
    "properties",
    "xml",
    "txt",
    "p12",
    "pfx",
    "pem",
    "key",
];

const SENSITIVE_EXACT_FILES: &[&str] = &[
    "google-services.json",
    "googleservice-info.plist",
    "local.properties",
    "master.key",
    "auth.json",
];

const SENSITIVE_DOTFILES: &[&str] = &[
    ".npmrc",
    ".pypirc",
    ".netrc",
    "_netrc",
    ".git-credentials",
    ".pgpass",
    ".my.cnf",
    ".htpasswd",
    ".yarnrc.yml",
    ".terraformrc",
];

const SENSITIVE_EXTENSIONS: &[&str] = &[
    "pem",
    "p12",
    "pfx",
    "p8",
    "kdbx",
    "ovpn",
    "rdp",
    "tfstate",
    "tfvars",
    "jks",
    "keystore",
    "mobileprovision",
];

const BENIGN_KEY_FILES: &[&str] = &["public.key", "license.key", "licence.key"];

pub fn is_suspicious(path: &str) -> bool {
    let path = path.replace('\\', "/");
    let name = Path::new(&path)
        .file_name()
        .and_then(|s| s.to_str())
        .unwrap_or("")
        .to_ascii_lowercase();
    let lower_path = path.to_ascii_lowercase();

    if name == ".env" || name.starts_with(".env.") || name.ends_with(".env") {
        return true;
    }
    if SENSITIVE_EXACT_FILES.iter().any(|f| name == *f) {
        return true;
    }
    if SENSITIVE_DOTFILES.iter().any(|f| name == *f) {
        return true;
    }

    let segments: Vec<&str> = lower_path.split('/').filter(|s| !s.is_empty()).collect();
    for (i, seg) in segments.iter().enumerate() {
        if SENSITIVE_DIRECTORY_COMPONENTS.iter().any(|d| d == seg) {
            return true;
        }
        if *seg == ".cargo" {
            if segments
                .get(i + 1)
                .is_some_and(|n| n.starts_with("credentials"))
            {
                return true;
            }
        }
    }

    for marker in SENSITIVE_BASENAMES {
        if name == *marker
            || name.starts_with(&format!("{marker}."))
            || name.starts_with(&format!("{marker}-"))
            || name.starts_with(&format!("{marker}_"))
        {
            return true;
        }
    }

    for marker in SECRET_DOCUMENT_BASENAMES {
        if name == *marker {
            return true;
        }
        for ext in SECRET_DOCUMENT_EXTENSIONS {
            if name == format!("{marker}.{ext}") {
                return true;
            }
        }
    }

    if let Some(ext) = Path::new(&name).extension().and_then(|s| s.to_str()) {
        if SENSITIVE_EXTENSIONS.iter().any(|e| *e == ext) {
            return true;
        }
        if ext == "key" && !BENIGN_KEY_FILES.iter().any(|b| name == *b) {
            return true;
        }
    }

    false
}

pub fn resolve_path(path: &str, cwd: Option<&str>) -> String {
    let p = Path::new(path);
    if p.is_absolute() {
        return normalize(path);
    }
    let base = cwd
        .filter(|s| !s.is_empty())
        .map(Path::new)
        .map(Path::to_path_buf)
        .unwrap_or_else(|| {
            std::env::current_dir().unwrap_or_else(|_| Path::new(".").to_path_buf())
        });
    normalize(&base.join(path).to_string_lossy())
}

pub fn sensitivity_check_paths(path: &str, cwd: Option<&str>) -> Vec<String> {
    let absolute = resolve_path(path, cwd);
    let mut out = vec![absolute.clone()];
    if let Ok(resolved) = std::fs::canonicalize(&absolute) {
        let r = resolved.to_string_lossy().to_string();
        if r != absolute {
            out.push(r);
        }
    }
    out
}

fn normalize(path: &str) -> String {
    // Lightweight normalize without requiring the path to exist.
    let mut parts = Vec::new();
    let absolute = path.starts_with('/');
    for part in path.replace('\\', "/").split('/') {
        match part {
            "" | "." => {}
            ".." => {
                parts.pop();
            }
            other => parts.push(other.to_string()),
        }
    }
    let joined = parts.join("/");
    if absolute {
        format!("/{joined}")
    } else if joined.is_empty() {
        ".".into()
    } else {
        joined
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn flags_env_and_pem() {
        assert!(is_suspicious("/proj/.env"));
        assert!(is_suspicious("/proj/.env.local"));
        assert!(is_suspicious("/home/u/.ssh/id_rsa"));
        assert!(is_suspicious("secrets.json"));
        assert!(!is_suspicious("src/main.rs"));
        assert!(!is_suspicious("public.key"));
    }
}
