//! Ignore file parsing and path matching — port of Swift ignore helpers.

use crate::glob::GlobPattern;

pub struct IgnoreFileParser;

impl IgnoreFileParser {
    pub fn normalized_pattern(line: &str) -> Option<String> {
        let trimmed = line.trim();
        if trimmed.is_empty() || trimmed.starts_with('#') {
            return None;
        }
        Some(trimmed.to_string())
    }

    pub fn patterns(contents: &str) -> std::collections::HashSet<String> {
        contents
            .lines()
            .filter_map(Self::normalized_pattern)
            .collect()
    }

    pub fn pattern_lines(contents: &str) -> Vec<String> {
        contents
            .lines()
            .filter_map(Self::normalized_pattern)
            .collect()
    }
}

/// Gitignore-like matching used by AI ignore files.
pub struct IgnorePatternPathMatcher;

impl IgnorePatternPathMatcher {
    pub fn matches(relative_path: &str, ignore_line: &str) -> bool {
        let mut pattern = ignore_line.trim().to_string();
        if pattern.is_empty() {
            return false;
        }

        let leading_slash = pattern.starts_with('/');
        if leading_slash {
            pattern.remove(0);
        }
        if pattern.ends_with('/') {
            pattern.pop();
        }
        if pattern.is_empty() {
            return false;
        }

        if leading_slash || pattern.contains('/') {
            matches_anchored(relative_path, &pattern)
        } else {
            matches_at_any_depth(relative_path, &pattern)
        }
    }

    /// Path is ignored when ≥1 positive match and no `!` reinclusion.
    /// Order is not preserved (same unordered Set semantics as Swift).
    pub fn is_ignored<'a>(relative_path: &str, ignore_lines: impl IntoIterator<Item = &'a str>) -> bool {
        let mut has_positive = false;
        let mut reincluded = false;
        for line in ignore_lines {
            if let Some(negated) = negation_body(line) {
                if Self::matches(relative_path, &negated) {
                    reincluded = true;
                }
            } else if Self::matches(relative_path, line) {
                has_positive = true;
            }
        }
        has_positive && !reincluded
    }

    /// Ignored if any ignore-file's pattern set covers the path (Swift multi-file OR).
    pub fn is_ignored_by_any_file(
        relative_path: &str,
        ignore_patterns_by_file: &std::collections::HashMap<String, std::collections::HashSet<String>>,
    ) -> bool {
        ignore_patterns_by_file.values().any(|patterns| {
            Self::is_ignored(relative_path, patterns.iter().map(String::as_str))
        })
    }
}

fn matches_anchored(relative_path: &str, pattern: &str) -> bool {
    if pattern.contains('*') || pattern.contains('?') {
        return GlobPattern::new(pattern).matches(relative_path);
    }
    relative_path == pattern || relative_path.starts_with(&(pattern.to_string() + "/"))
}

fn matches_at_any_depth(relative_path: &str, pattern: &str) -> bool {
    let segments: Vec<&str> = relative_path
        .split('/')
        .filter(|s| !s.is_empty())
        .collect();
    if pattern.contains('*') || pattern.contains('?') {
        let glob = GlobPattern::new(pattern);
        return segments.iter().any(|seg| glob.matches(seg));
    }
    segments.iter().any(|seg| *seg == pattern)
}

fn negation_body(line: &str) -> Option<String> {
    let trimmed = line.trim();
    if trimmed.starts_with('!') && trimmed.len() > 1 {
        Some(trimmed[1..].to_string())
    } else {
        None
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn basename_glob_any_depth() {
        assert!(IgnorePatternPathMatcher::matches("certs/server.pem", "*.pem"));
        assert!(IgnorePatternPathMatcher::matches("server.pem", "*.pem"));
    }

    #[test]
    fn anchored_prefix() {
        assert!(IgnorePatternPathMatcher::matches("secrets/a.env", "/secrets"));
        assert!(IgnorePatternPathMatcher::matches("secrets/a.env", "secrets/"));
        assert!(!IgnorePatternPathMatcher::matches("other/secrets/a.env", "/secrets"));
    }

    #[test]
    fn negation() {
        let lines = [".env", "!.env.example"];
        assert!(IgnorePatternPathMatcher::is_ignored(".env", lines));
        assert!(!IgnorePatternPathMatcher::is_ignored(".env.example", lines));
    }

    #[test]
    fn parser_skips_comments() {
        let set = IgnoreFileParser::patterns("# hi\n\n*.pem\n  # x\n.env\n");
        assert!(set.contains("*.pem"));
        assert!(set.contains(".env"));
        assert_eq!(set.len(), 2);
    }
}
