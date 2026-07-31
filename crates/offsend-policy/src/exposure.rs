//! Path-only sensitive exposure — port of Swift `SensitivePathMatcher` /
//! `SensitivePathExposureChecker` (without incremental index updates).

use crate::allowlist::is_allowlisted_default;
use crate::audit_model::{
    ExposureIndex, ExposureScanCompletion, ExposureScanLimits, ExposureScanResult,
    ExposedFileFinding, SensitivePattern,
};
use crate::glob::GlobPattern;
use crate::ignore::IgnorePatternPathMatcher;
use std::collections::{HashMap, HashSet};
use std::path::Path;
use std::time::Instant;

pub const BUILTIN_SKIPPED_DIRECTORY_NAMES: &[&str] =
    &[".git", "node_modules", ".build", "build", "DerivedData"];

pub fn matching_pattern<'a>(
    relative_path: &str,
    patterns: &'a [SensitivePattern],
) -> Option<&'a SensitivePattern> {
    patterns.iter().find(|pattern| {
        pattern
            .accepted_patterns
            .iter()
            .any(|p| GlobPattern::new(p).matches(relative_path))
    })
}

pub fn exposed_finding(
    relative_path: &str,
    sensitive_patterns: &[SensitivePattern],
    ignore_patterns_by_file: &HashMap<String, HashSet<String>>,
) -> Option<ExposedFileFinding> {
    if is_allowlisted_default(relative_path) {
        return None;
    }
    let pattern = matching_pattern(relative_path, sensitive_patterns)?;
    if IgnorePatternPathMatcher::is_ignored_by_any_file(relative_path, ignore_patterns_by_file) {
        return None;
    }
    Some(ExposedFileFinding {
        relative_path: relative_path.to_string(),
        pattern: pattern.clone(),
    })
}

pub fn exposed_among(
    relative_paths: impl IntoIterator<Item = impl AsRef<str>>,
    sensitive_patterns: &[SensitivePattern],
    ignore_patterns_by_file: &HashMap<String, HashSet<String>>,
) -> Vec<ExposedFileFinding> {
    let mut seen = HashSet::new();
    let mut findings = Vec::new();
    for path in relative_paths {
        let path = path.as_ref();
        if !seen.insert(path.to_string()) {
            continue;
        }
        if let Some(f) = exposed_finding(path, sensitive_patterns, ignore_patterns_by_file) {
            findings.push(f);
        }
    }
    findings.sort_by(|a, b| a.relative_path.cmp(&b.relative_path));
    findings
}

/// Walk `root` (file names only). Never reads sensitive file bodies.
pub fn scan_directory(
    root: &Path,
    sensitive_patterns: &[SensitivePattern],
    ignore_patterns_by_file: &HashMap<String, HashSet<String>>,
    skipped_directory_names: &HashSet<String>,
    limits: ExposureScanLimits,
) -> ExposureScanResult {
    if !root.is_dir() {
        return ExposureScanResult {
            exposed_files: vec![],
            indexed_sensitive_paths: HashSet::new(),
            files_scanned: 0,
            completion: ExposureScanCompletion::Complete,
        };
    }

    let started = Instant::now();
    let mut exposed = Vec::new();
    let mut indexed = HashSet::new();
    let mut files_scanned = 0usize;
    let mut completion = ExposureScanCompletion::Complete;
    let mut stack = vec![root.to_path_buf()];

    'walk: while let Some(dir) = stack.pop() {
        let entries = match std::fs::read_dir(&dir) {
            Ok(e) => e,
            Err(_) => continue,
        };
        for entry in entries.flatten() {
            let path = entry.path();
            let Ok(meta) = entry.metadata() else { continue };
            if meta.is_dir() {
                let name = entry.file_name().to_string_lossy().to_string();
                if skipped_directory_names.contains(&name) {
                    continue;
                }
                stack.push(path);
                continue;
            }
            if !meta.is_file() {
                continue;
            }

            files_scanned += 1;
            if let Some(max) = limits.max_files {
                if files_scanned > max {
                    completion = ExposureScanCompletion::Truncated {
                        max_files: max,
                        files_scanned: files_scanned - 1,
                    };
                    break 'walk;
                }
            }
            if let Some(limit) = limits.time_limit {
                if started.elapsed() >= limit {
                    completion = ExposureScanCompletion::TimedOut {
                        time_limit_secs: limit.as_secs_f64(),
                        files_scanned: files_scanned - 1,
                    };
                    break 'walk;
                }
            }

            let Some(rel) = relative_path(root, &path) else {
                continue;
            };
            if is_allowlisted_default(&rel) {
                continue;
            }
            if matching_pattern(&rel, sensitive_patterns).is_some() {
                indexed.insert(rel.clone());
            }
            if let Some(f) = exposed_finding(&rel, sensitive_patterns, ignore_patterns_by_file) {
                exposed.push(f);
            }
        }
    }

    exposed.sort_by(|a, b| a.relative_path.cmp(&b.relative_path));
    ExposureScanResult {
        exposed_files: exposed,
        indexed_sensitive_paths: indexed,
        files_scanned,
        completion,
    }
}

pub fn exposure_index_from_scan(scan: &ExposureScanResult) -> ExposureIndex {
    ExposureIndex {
        sensitive_relative_paths: scan.indexed_sensitive_paths.clone(),
    }
}

fn relative_path(root: &Path, file: &Path) -> Option<String> {
    let rel = file.strip_prefix(root).ok()?;
    Some(rel.to_string_lossy().replace('\\', "/"))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::defaults::DEFAULT_SENSITIVE_PATTERNS;
    use std::fs;

    #[test]
    fn matches_pem_and_allowlists_example() {
        let patterns = DEFAULT_SENSITIVE_PATTERNS.as_slice();
        assert!(matching_pattern("certs/server.pem", patterns).is_some());
        assert!(matching_pattern(".env", patterns).is_some());
        let empty = HashMap::new();
        assert!(exposed_finding(".env.example", patterns, &empty).is_none());
        assert!(exposed_finding("server.pem", patterns, &empty).is_some());
    }

    #[test]
    fn ignore_covers_exposure() {
        let patterns = DEFAULT_SENSITIVE_PATTERNS.as_slice();
        let mut by_file = HashMap::new();
        by_file.insert(
            ".cursorignore".into(),
            [".env".into(), "*.pem".into()].into_iter().collect(),
        );
        assert!(exposed_finding(".env", patterns, &by_file).is_none());
        assert!(exposed_finding("a.pem", patterns, &by_file).is_none());
        assert!(exposed_finding("secrets.json", patterns, &by_file).is_some());
    }

    #[test]
    fn scan_temp_dir() {
        let dir = std::env::temp_dir().join(format!("offsend-policy-audit-{}", std::process::id()));
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(dir.join("certs")).unwrap();
        fs::write(dir.join("certs/server.pem"), "x").unwrap();
        fs::write(dir.join(".env.example"), "x").unwrap();
        fs::write(dir.join("readme.txt"), "x").unwrap();

        let patterns = DEFAULT_SENSITIVE_PATTERNS.as_slice();
        let empty = HashMap::new();
        let skipped: HashSet<_> = BUILTIN_SKIPPED_DIRECTORY_NAMES
            .iter()
            .map(|s| (*s).to_string())
            .collect();
        let result = scan_directory(
            &dir,
            patterns,
            &empty,
            &skipped,
            ExposureScanLimits::UNLIMITED,
        );
        let _ = fs::remove_dir_all(&dir);

        assert!(result
            .exposed_files
            .iter()
            .any(|f| f.relative_path == "certs/server.pem"));
        assert!(!result
            .exposed_files
            .iter()
            .any(|f| f.relative_path == ".env.example"));
        assert!(result.completion.is_complete());
    }
}
