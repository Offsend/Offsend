//! `check.exclude` matcher — port of Swift `PathExcludeMatcher`.

use crate::glob::GlobPattern;

pub struct PathExcludeMatcher;

impl PathExcludeMatcher {
    pub fn is_excluded(relative_path: &str, patterns: &[String]) -> bool {
        let normalized = normalize(relative_path);
        if normalized.is_empty() {
            return false;
        }
        patterns.iter().any(|p| matches_pattern(p, &normalized))
    }

    pub fn should_skip_directory(relative_path: &str, patterns: &[String]) -> bool {
        let normalized = normalize(relative_path);
        if normalized.is_empty() {
            return false;
        }
        if normalized == ".git" || normalized.ends_with("/.git") {
            return true;
        }
        Self::is_excluded(&normalized, patterns)
    }
}

fn normalize(relative_path: &str) -> String {
    let mut path = relative_path.replace('\\', "/");
    while path.starts_with("./") {
        path = path[2..].to_string();
    }
    if path.starts_with('/') {
        path = path[1..].to_string();
    }
    path
}

fn matches_pattern(pattern: &str, relative_path: &str) -> bool {
    if let Some(body) = pattern.strip_suffix("/**") {
        return matches_directory_tree(body, relative_path);
    }
    if let Some(rest) = pattern.strip_prefix("**/") {
        return matches_any_depth(rest, relative_path);
    }
    if pattern.contains('/') {
        return GlobPattern::new(pattern).matches(relative_path);
    }

    if let Some(slash) = relative_path.rfind('/') {
        let file_name = &relative_path[slash + 1..];
        return GlobPattern::new(pattern).matches(file_name)
            || GlobPattern::new(pattern).matches(relative_path);
    }
    GlobPattern::new(pattern).matches(relative_path)
}

fn matches_any_depth(rest: &str, relative_path: &str) -> bool {
    if rest.contains('/') {
        return relative_path == rest || relative_path.ends_with(&format!("/{rest}"));
    }
    let file_name = relative_path
        .rsplit_once('/')
        .map(|(_, name)| name)
        .unwrap_or(relative_path);
    GlobPattern::new(rest).matches(file_name)
}

fn matches_directory_tree(body: &str, relative_path: &str) -> bool {
    if let Some(rest) = body.strip_prefix("**/") {
        return path_has_matching_segment(relative_path, rest);
    }
    if body.contains('*') || body.contains('?') || body.contains('[') {
        return path_has_matching_segment(relative_path, body);
    }
    relative_path == body || relative_path.starts_with(&(body.to_string() + "/"))
}

fn path_has_matching_segment(relative_path: &str, segment_pattern: &str) -> bool {
    let glob = GlobPattern::new(segment_pattern);
    let segments: Vec<&str> = relative_path.split('/').filter(|s| !s.is_empty()).collect();
    // Match a segment, or a trailing path starting at a matching segment prefix for nested rests.
    if segment_pattern.contains('/') {
        return relative_path == segment_pattern
            || relative_path.ends_with(&format!("/{segment_pattern}"))
            || relative_path.contains(&format!("/{segment_pattern}/"));
    }
    segments.iter().any(|seg| glob.matches(seg))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn pats(xs: &[&str]) -> Vec<String> {
        xs.iter().map(|s| (*s).to_string()).collect()
    }

    #[test]
    fn directory_tree_and_basename() {
        let p = pats(&["target/**", "*.lock"]);
        assert!(PathExcludeMatcher::is_excluded("target/debug/foo", &p));
        assert!(PathExcludeMatcher::is_excluded("target", &p));
        assert!(PathExcludeMatcher::is_excluded("Cargo.lock", &p));
        assert!(PathExcludeMatcher::is_excluded("pkg/Cargo.lock", &p));
        assert!(!PathExcludeMatcher::is_excluded("src/main.rs", &p));
    }

    #[test]
    fn any_depth_prefix() {
        let p = pats(&["**/Info.plist"]);
        assert!(PathExcludeMatcher::is_excluded("Info.plist", &p));
        assert!(PathExcludeMatcher::is_excluded("App/Info.plist", &p));
    }

    #[test]
    fn skips_git() {
        assert!(PathExcludeMatcher::should_skip_directory(".git", &[]));
    }
}
