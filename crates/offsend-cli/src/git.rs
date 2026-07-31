//! Minimal git helpers for `check --staged`.

use std::path::{Path, PathBuf};
use std::process::Command;
use thiserror::Error;

#[derive(Debug, Error)]
pub enum GitError {
    #[error("git executable not found.")]
    NotFound,
    #[error("Not a git repository: {0}")]
    NotARepo(String),
    #[error("git command failed: {0}")]
    CommandFailed(String),
}

pub fn repository_root(start: &Path) -> Result<PathBuf, GitError> {
    let output = run(start, &["rev-parse", "--show-toplevel"])?;
    let root = output.trim();
    if root.is_empty() {
        return Err(GitError::NotARepo(start.display().to_string()));
    }
    Ok(PathBuf::from(root))
}

/// Staged paths relative to the repository root (ACMR only).
pub fn staged_paths(repo_root: &Path) -> Result<Vec<String>, GitError> {
    let output = run(
        repo_root,
        &[
            "diff",
            "--cached",
            "--name-only",
            "--diff-filter=ACMR",
            "-z",
        ],
    )?;
    if output.is_empty() {
        return Ok(Vec::new());
    }
    Ok(output
        .split('\0')
        .filter(|s| !s.is_empty())
        .map(str::to_string)
        .collect())
}

/// All tracked paths relative to the repository root (`git ls-files -z`).
pub fn tracked_paths(repo_root: &Path) -> Result<Vec<String>, GitError> {
    let output = run(repo_root, &["ls-files", "-z"])?;
    if output.is_empty() {
        return Ok(Vec::new());
    }
    Ok(output
        .split('\0')
        .filter(|s| !s.is_empty())
        .map(str::to_string)
        .collect())
}

/// Blob contents of a staged path (`git show :path`).
pub fn staged_blob(repo_root: &Path, relative: &str) -> Result<Vec<u8>, GitError> {
    let spec = format!(":{relative}");
    let mut cmd = Command::new("git");
    cmd.current_dir(repo_root)
        .args(["show", &spec])
        .stdout(std::process::Stdio::piped())
        .stderr(std::process::Stdio::piped());
    let output = cmd.output().map_err(|_| GitError::NotFound)?;
    if !output.status.success() {
        let err = String::from_utf8_lossy(&output.stderr);
        return Err(GitError::CommandFailed(err.trim().to_string()));
    }
    Ok(output.stdout)
}

fn run(cwd: &Path, args: &[&str]) -> Result<String, GitError> {
    let output = Command::new("git")
        .current_dir(cwd)
        .args(args)
        .output()
        .map_err(|_| GitError::NotFound)?;
    if !output.status.success() {
        let err = String::from_utf8_lossy(&output.stderr);
        if err.contains("not a git repository") {
            return Err(GitError::NotARepo(cwd.display().to_string()));
        }
        return Err(GitError::CommandFailed(err.trim().to_string()));
    }
    Ok(String::from_utf8_lossy(&output.stdout).into_owned())
}
