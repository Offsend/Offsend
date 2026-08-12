//! Git hooks — `pre-commit` (staged check) and `post-merge` (tree check after pull/merge).

use std::fs;
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};
use thiserror::Error;

pub const MANAGED_MARKER: &str = "# offsend-managed";
pub const MANAGED_VERSION: &str = "v1";

#[derive(Debug, Error)]
pub enum GitHookError {
    #[error("Not a git repository: {0}")]
    NotARepository(String),
    #[error("Hook already installed at {0} (use --force to overwrite).")]
    AlreadyInstalled(String),
    #[error("Hook is not installed at {0}.")]
    NotInstalled(String),
    #[error("Hook at {0} was modified and is no longer managed by Offsend (use --force).")]
    Modified(String),
    #[error("Unsupported git hook {0:?}. Supported: pre-commit, post-merge.")]
    Unsupported(String),
    #[error("{0}")]
    Message(String),
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum GitHookKind {
    PreCommit,
    PostMerge,
}

impl GitHookKind {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::PreCommit => "pre-commit",
            Self::PostMerge => "post-merge",
        }
    }

    pub fn parse(raw: &str) -> Option<Self> {
        match raw.trim().to_ascii_lowercase().as_str() {
            "pre-commit" => Some(Self::PreCommit),
            "post-merge" => Some(Self::PostMerge),
            _ => None,
        }
    }

    pub fn all() -> &'static [Self] {
        &[Self::PreCommit, Self::PostMerge]
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum HookState {
    Installed,
    NotInstalled,
    Modified,
}

#[derive(Debug, Clone)]
pub struct HookStatus {
    #[allow(dead_code)]
    pub repository_path: PathBuf,
    #[allow(dead_code)]
    pub kind: GitHookKind,
    pub hook_path: PathBuf,
    pub state: HookState,
}

pub fn resolve_repo_root(start: &Path) -> Result<PathBuf, GitHookError> {
    let mut candidate = if start.is_dir() {
        start.to_path_buf()
    } else {
        start
            .parent()
            .map(Path::to_path_buf)
            .unwrap_or_else(|| start.to_path_buf())
    };
    loop {
        if candidate.join(".git").exists() {
            return Ok(candidate);
        }
        if !candidate.pop() {
            break;
        }
    }
    Err(GitHookError::NotARepository(start.display().to_string()))
}

pub fn hook_path(repo: &Path, kind: GitHookKind) -> PathBuf {
    repo.join(".git/hooks").join(kind.as_str())
}

pub fn is_managed(contents: &str) -> bool {
    contents
        .lines()
        .take(2)
        .any(|line| line.trim().starts_with(MANAGED_MARKER))
}

pub fn make_script(kind: GitHookKind, cli_path: &str, fail_on: &str, include_policy: bool) -> String {
    // pre-commit: block secrets on the way in.
    // post-merge: after pull/merge, re-apply .offsend.yml (ignore files + hooks).
    let args: Vec<String> = match kind {
        GitHookKind::PreCommit => {
            let mut args = vec![
                "check".into(),
                "--staged".into(),
                "--fail-on".into(),
                fail_on.to_string(),
            ];
            if include_policy {
                args.push("--policy".into());
            }
            args
        }
        GitHookKind::PostMerge => vec!["sync".into()],
    };
    let quoted_args: Vec<_> = args.iter().map(|a| shell_quote(a)).collect();
    let bypass = match kind {
        GitHookKind::PreCommit => "git commit --no-verify",
        GitHookKind::PostMerge => "remove .git/hooks/post-merge or rename it",
    };
    format!(
        "#!/bin/sh\n{MANAGED_MARKER} {MANAGED_VERSION}\nOFFSEND_BIN={bin}\nif [ ! -x \"$OFFSEND_BIN\" ]; then\n  OFFSEND_BIN=\"$(command -v offsend 2>/dev/null || true)\"\nfi\nif [ -z \"$OFFSEND_BIN\" ]; then\n  echo \"offsend: executable not found; reinstall the hook with 'offsend hook install' or bypass with '{bypass}'\" >&2\n  exit 2\nfi\nexec \"$OFFSEND_BIN\" {args}\n",
        bin = shell_quote(cli_path),
        args = quoted_args.join(" "),
        bypass = bypass,
    )
}

pub fn install(
    repo_start: &Path,
    kind: GitHookKind,
    cli_path: &str,
    fail_on: &str,
    include_policy: bool,
    force: bool,
) -> Result<PathBuf, GitHookError> {
    let root = resolve_repo_root(repo_start)?;
    let path = hook_path(&root, kind);
    if path.is_file() {
        let existing = fs::read_to_string(&path).unwrap_or_default();
        if !is_managed(&existing) && !force {
            return Err(GitHookError::AlreadyInstalled(path.display().to_string()));
        }
    }
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent).map_err(|e| GitHookError::Message(e.to_string()))?;
    }
    let script = make_script(kind, cli_path, fail_on, include_policy);
    // Idempotent: a repeated `offsend sync` must not rewrite an identical hook.
    if path.is_file() {
        let current = fs::read_to_string(&path).unwrap_or_default();
        let executable = fs::metadata(&path)
            .map(|m| m.permissions().mode() & 0o111 != 0)
            .unwrap_or(false);
        if current == script && executable {
            return Ok(path);
        }
    }
    fs::write(&path, script).map_err(|e| GitHookError::Message(e.to_string()))?;
    let mut perms = fs::metadata(&path)
        .map_err(|e| GitHookError::Message(e.to_string()))?
        .permissions();
    perms.set_mode(0o755);
    fs::set_permissions(&path, perms).map_err(|e| GitHookError::Message(e.to_string()))?;
    Ok(path)
}

pub fn uninstall(repo_start: &Path, kind: GitHookKind, force: bool) -> Result<(), GitHookError> {
    let root = resolve_repo_root(repo_start)?;
    let path = hook_path(&root, kind);
    if !path.is_file() {
        return Err(GitHookError::NotInstalled(path.display().to_string()));
    }
    let existing = fs::read_to_string(&path).unwrap_or_default();
    if !is_managed(&existing) && !force {
        return Err(GitHookError::Modified(path.display().to_string()));
    }
    fs::remove_file(&path).map_err(|e| GitHookError::Message(e.to_string()))?;
    Ok(())
}

pub fn status(repo_start: &Path, kind: GitHookKind) -> Result<HookStatus, GitHookError> {
    let root = resolve_repo_root(repo_start)?;
    let path = hook_path(&root, kind);
    let state = if !path.is_file() {
        HookState::NotInstalled
    } else {
        let contents = fs::read_to_string(&path).unwrap_or_default();
        if is_managed(&contents) {
            HookState::Installed
        } else {
            HookState::Modified
        }
    };
    Ok(HookStatus {
        repository_path: root,
        kind,
        hook_path: path,
        state,
    })
}

pub fn parse_kinds(names: &[String]) -> Result<Vec<GitHookKind>, GitHookError> {
    let mut out = Vec::new();
    for name in names {
        match GitHookKind::parse(name) {
            Some(kind) if !out.contains(&kind) => out.push(kind),
            Some(_) => {}
            None => return Err(GitHookError::Unsupported(name.clone())),
        }
    }
    Ok(out)
}

fn shell_quote(value: &str) -> String {
    if value
        .chars()
        .all(|c| c.is_ascii_alphanumeric() || matches!(c, '_' | '.' | '/' | ':' | '-'))
    {
        value.to_string()
    } else {
        format!("'{}'", value.replace('\'', "'\\''"))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn pre_commit_script_uses_staged() {
        let s = make_script(GitHookKind::PreCommit, "/usr/bin/offsend", "block", false);
        assert!(s.contains("--staged"));
        assert!(!s.contains("check ."));
    }

    #[test]
    fn post_merge_script_runs_sync() {
        let s = make_script(GitHookKind::PostMerge, "/usr/bin/offsend", "block", true);
        assert!(s.contains(" sync\n") || s.contains(" sync"));
        assert!(!s.contains("--staged"));
        assert!(!s.contains(" check "));
    }
}
