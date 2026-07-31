//! Managed-ignore drift — port of Swift `OffsendManagedIgnoreDrift` core compare.

use crate::ignore::IgnoreFileParser;
use crate::managed_block::ManagedIgnoreBlock;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ManagedIgnoreDriftFinding {
    pub relative_path: String,
    pub missing_patterns: Vec<String>,
}

/// Patterns from `ignore.patterns` missing in a single ignore file's contents.
///
/// Prefer the managed block when present; otherwise use all non-comment lines.
pub fn drift_missing_patterns(expected: &[String], contents: &str) -> Vec<String> {
    let expected = ManagedIgnoreBlock::normalize_patterns(expected);
    if expected.is_empty() {
        return Vec::new();
    }
    let present: std::collections::HashSet<String> =
        if let Some(managed) = ManagedIgnoreBlock::patterns(contents, None) {
            managed.into_iter().collect()
        } else {
            IgnoreFileParser::patterns(contents)
        };
    let mut missing: Vec<_> = expected
        .into_iter()
        .filter(|p| !present.contains(p))
        .collect();
    missing.sort();
    missing
}

/// Compare expected patterns against a map of relative_path → file contents.
/// Skips paths with no contents (missing files are not drift findings here).
pub fn findings_for_files(
    expected: &[String],
    files: &[(String, String)],
) -> Vec<ManagedIgnoreDriftFinding> {
    let mut out = Vec::new();
    for (relative_path, contents) in files {
        let missing = drift_missing_patterns(expected, contents);
        if !missing.is_empty() {
            out.push(ManagedIgnoreDriftFinding {
                relative_path: relative_path.clone(),
                missing_patterns: missing,
            });
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn managed_block_precedence() {
        let expected = vec![".env".into(), "*.pem".into(), "secrets/".into()];
        let contents = concat!(
            "# user junk\n",
            "# >>> offsend managed\n",
            ".env\n",
            "*.pem\n",
            "# <<< offsend managed\n",
            "other\n",
        );
        assert_eq!(
            drift_missing_patterns(&expected, contents),
            vec!["secrets/".to_string()]
        );
    }

    #[test]
    fn whole_file_fallback() {
        let expected = vec![".env".into(), "*.pem".into()];
        let contents = ".env\n# comment\n";
        assert_eq!(
            drift_missing_patterns(&expected, contents),
            vec!["*.pem".to_string()]
        );
    }

    #[test]
    fn findings_map() {
        let expected = vec![".env".into()];
        let files = vec![
            (".cursorignore".into(), ".env\n".into()),
            (".claudeignore".into(), "*.pem\n".into()),
        ];
        let f = findings_for_files(&expected, &files);
        assert_eq!(f.len(), 1);
        assert_eq!(f[0].relative_path, ".claudeignore");
        assert_eq!(f[0].missing_patterns, vec![".env".to_string()]);
    }
}
