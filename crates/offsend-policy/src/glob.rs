//! Minimal glob matcher — port of Swift `GlobPattern`.
//!
//! Supports `*`, `**`, `**/`, and `?`. Character classes and braces are literals.

use once_cell::sync::Lazy;
use regex::Regex;
use std::collections::HashMap;
use std::sync::Mutex;

pub struct GlobPattern {
    regex: Regex,
}

impl GlobPattern {
    pub fn new(pattern: &str) -> Self {
        let regex = cache_regex(pattern);
        Self { regex }
    }

    pub fn matches(&self, value: &str) -> bool {
        self.regex.is_match(value)
    }

    /// Translate a glob to an unanchored regex body (Swift `regexPattern(from:)`).
    pub fn regex_body(glob: &str) -> String {
        let mut regex = String::new();
        let bytes = glob.as_bytes();
        let mut i = 0;
        while i < bytes.len() {
            let c = bytes[i] as char;
            if c == '*' {
                if i + 1 < bytes.len() && bytes[i + 1] as char == '*' {
                    if i + 2 < bytes.len() && bytes[i + 2] as char == '/' {
                        regex.push_str("(?:.*/)?");
                        i += 3;
                    } else {
                        regex.push_str(".*");
                        i += 2;
                    }
                } else {
                    regex.push_str("[^/]*");
                    i += 1;
                }
            } else if c == '?' {
                regex.push_str("[^/]");
                i += 1;
            } else {
                regex.push_str(&regex::escape(&c.to_string()));
                i += 1;
            }
        }
        regex
    }
}

fn cache_regex(pattern: &str) -> Regex {
    static CACHE: Lazy<Mutex<HashMap<String, Regex>>> =
        Lazy::new(|| Mutex::new(HashMap::new()));
    const MAX: usize = 4096;

    let mut guard = CACHE.lock().expect("glob cache");
    if let Some(re) = guard.get(pattern) {
        return re.clone();
    }
    if guard.len() >= MAX {
        guard.clear();
    }
    let anchored = format!("^{}$", GlobPattern::regex_body(pattern));
    let compiled = Regex::new(&anchored)
        .or_else(|_| Regex::new(&format!("^{}$", regex::escape(pattern))))
        .unwrap_or_else(|_| Regex::new(r"\b\B").expect("never-matching"));
    guard.insert(pattern.to_string(), compiled.clone());
    compiled
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn star_within_segment() {
        assert!(GlobPattern::new("*.pem").matches("server.pem"));
        assert!(!GlobPattern::new("*.pem").matches("certs/server.pem"));
    }

    #[test]
    fn double_star_slash_matches_root() {
        assert!(GlobPattern::new("**/*.mdc").matches("a.mdc"));
        assert!(GlobPattern::new("**/*.mdc").matches("dir/a.mdc"));
    }

    #[test]
    fn question_mark() {
        assert!(GlobPattern::new("?.txt").matches("a.txt"));
        assert!(!GlobPattern::new("?.txt").matches("ab.txt"));
        assert!(!GlobPattern::new("?.txt").matches("a/b.txt"));
    }

    #[test]
    fn braces_are_literal() {
        assert!(GlobPattern::new("{a,b}.txt").matches("{a,b}.txt"));
        assert!(!GlobPattern::new("{a,b}.txt").matches("a.txt"));
    }
}
