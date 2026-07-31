//! Managed ignore block markers — port of Swift `OffsendManagedIgnoreBlock`.

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum UpsertResult {
    Created,
    Updated,
    Unchanged,
    Malformed(String),
}

pub struct ManagedIgnoreBlock;

impl ManagedIgnoreBlock {
    pub const START_MARKER: &'static str = "# >>> offsend managed";
    pub const END_MARKER: &'static str = "# <<< offsend managed";

    pub fn start_marker(section: Option<&str>) -> String {
        match section {
            Some(s) => format!("{}: {s}", Self::START_MARKER),
            None => Self::START_MARKER.to_string(),
        }
    }

    pub fn end_marker(section: Option<&str>) -> String {
        match section {
            Some(s) => format!("{}: {s}", Self::END_MARKER),
            None => Self::END_MARKER.to_string(),
        }
    }

    pub fn upsert(
        patterns: &[String],
        contents: Option<&str>,
        section: Option<&str>,
    ) -> (String, UpsertResult) {
        let normalized = Self::normalize_patterns(patterns);
        let block_lines = Self::render_block_lines(&normalized, section);

        let Some(existing) = contents else {
            return (
                block_lines.join("\n") + "\n",
                UpsertResult::Created,
            );
        };

        let lines = split_lines(existing);
        let ranges = match block_ranges(&lines, section) {
            Err(message) => {
                return (ensure_trailing_newline(existing), UpsertResult::Malformed(message));
            }
            Ok(found) => found,
        };

        let new_lines: Vec<String> = if ranges.is_empty() {
            let mut out = lines;
            if let Some(last) = out.last() {
                if !last.is_empty() {
                    out.push(String::new());
                }
            }
            out.extend(block_lines.iter().cloned());
            out
        } else {
            let mut out = Vec::new();
            let mut index = 0;
            let mut replaced = false;
            while index < lines.len() {
                if let Some(range) = ranges.iter().find(|r| *r.start() == index) {
                    if !replaced {
                        out.extend(block_lines.iter().cloned());
                        replaced = true;
                    }
                    index = *range.end() + 1;
                    continue;
                }
                out.push(lines[index].clone());
                index += 1;
            }
            out
        };

        let updated = if new_lines.is_empty() {
            block_lines.join("\n") + "\n"
        } else {
            new_lines.join("\n") + "\n"
        };

        if updated == ensure_trailing_newline(existing) {
            (updated, UpsertResult::Unchanged)
        } else {
            (updated, UpsertResult::Updated)
        }
    }

    pub fn removing(section: Option<&str>, contents: &str) -> Option<String> {
        let lines = split_lines(contents);
        let ranges = block_ranges(&lines, section).ok()?;
        if ranges.is_empty() {
            return None;
        }
        let mut new_lines = Vec::new();
        let mut index = 0;
        while index < lines.len() {
            if let Some(range) = ranges.iter().find(|r| *r.start() == index) {
                index = *range.end() + 1;
                continue;
            }
            new_lines.push(lines[index].clone());
            index += 1;
        }
        while new_lines.last().map(|s| s.is_empty()).unwrap_or(false) {
            new_lines.pop();
        }
        if new_lines.is_empty() {
            return Some(String::new());
        }
        Some(new_lines.join("\n") + "\n")
    }

    pub fn patterns(contents: &str, section: Option<&str>) -> Option<Vec<String>> {
        let lines = split_lines(contents);
        let ranges = block_ranges(&lines, section).ok()?;
        let range = ranges.first()?;
        if range.end() - range.start() < 2 {
            return Some(Vec::new());
        }
        let inner: Vec<String> = lines[(*range.start() + 1)..*range.end()].to_vec();
        Some(Self::normalize_patterns(&inner))
    }

    pub fn normalize_patterns(patterns: &[String]) -> Vec<String> {
        let mut seen = std::collections::HashSet::new();
        let mut result = Vec::new();
        for raw in patterns {
            let trimmed = raw.trim();
            if trimmed.is_empty() || trimmed.starts_with('#') {
                continue;
            }
            if seen.insert(trimmed.to_string()) {
                result.push(trimmed.to_string());
            }
        }
        result
    }

    pub fn render_block(patterns: &[String], section: Option<&str>) -> String {
        Self::render_block_lines(patterns, section).join("\n")
    }

    fn render_block_lines(patterns: &[String], section: Option<&str>) -> Vec<String> {
        let mut lines = vec![Self::start_marker(section)];
        lines.extend(patterns.iter().cloned());
        lines.push(Self::end_marker(section));
        lines
    }
}

fn block_ranges(
    lines: &[String],
    section: Option<&str>,
) -> Result<Vec<std::ops::RangeInclusive<usize>>, String> {
    let start = ManagedIgnoreBlock::start_marker(section);
    let end = ManagedIgnoreBlock::end_marker(section);
    let mut ranges = Vec::new();
    let mut open_index: Option<usize> = None;
    for (index, line) in lines.iter().enumerate() {
        let trimmed = line.trim();
        if trimmed == start {
            if open_index.is_some() {
                return Err(
                    "Ignore file has a broken offsend managed block (nested start marker)."
                        .into(),
                );
            }
            open_index = Some(index);
        } else if trimmed == end {
            let Some(open) = open_index else {
                return Err(
                    "Ignore file has a broken offsend managed block (end marker without start)."
                        .into(),
                );
            };
            ranges.push(open..=index);
            open_index = None;
        }
    }
    if open_index.is_some() {
        return Err(
            "Ignore file has a broken offsend managed block (missing end marker).".into(),
        );
    }
    Ok(ranges)
}

fn split_lines(contents: &str) -> Vec<String> {
    let mut lines: Vec<String> = contents.split('\n').map(String::from).collect();
    if lines.last().map(|s| s.is_empty()).unwrap_or(false) {
        lines.pop();
    }
    lines
}

fn ensure_trailing_newline(text: &str) -> String {
    if text.ends_with('\n') {
        text.to_string()
    } else {
        format!("{text}\n")
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn creates_and_updates_block() {
        let patterns = vec![".env".into(), "*.pem".into()];
        let (created, result) = ManagedIgnoreBlock::upsert(&patterns, None, None);
        assert_eq!(result, UpsertResult::Created);
        assert!(created.contains(ManagedIgnoreBlock::START_MARKER));
        assert!(created.contains(".env"));

        let (again, result) = ManagedIgnoreBlock::upsert(&patterns, Some(&created), None);
        assert_eq!(result, UpsertResult::Unchanged);
        let _ = again;

        let more = vec![".env".into(), "*.pem".into(), "secrets/".into()];
        let (updated, result) = ManagedIgnoreBlock::upsert(&more, Some(&created), None);
        assert_eq!(result, UpsertResult::Updated);
        assert!(updated.contains("secrets/"));
        assert!(updated.matches(ManagedIgnoreBlock::START_MARKER).count() == 1);
    }

    #[test]
    fn sectioned_markers_independent() {
        let base = "# user\nkeep-me\n";
        let (with_a, _) = ManagedIgnoreBlock::upsert(
            &[".cursorignore".into()],
            Some(base),
            Some("ignore-files"),
        );
        let (with_both, _) = ManagedIgnoreBlock::upsert(
            &[".env".into()],
            Some(&with_a),
            None,
        );
        assert!(with_both.contains("keep-me"));
        assert!(with_both.contains("# >>> offsend managed: ignore-files"));
        assert!(with_both.contains("# >>> offsend managed\n.env\n"));
    }

    #[test]
    fn malformed_nested_start() {
        let bad = "# >>> offsend managed\n# >>> offsend managed\n# <<< offsend managed\n";
        let (out, result) = ManagedIgnoreBlock::upsert(&[".env".into()], Some(bad), None);
        assert!(matches!(result, UpsertResult::Malformed(_)));
        assert_eq!(out, bad); // ensure trailing newline already present
    }

    #[test]
    fn patterns_from_block() {
        let contents = "# >>> offsend managed\n.env\n*.pem\n# <<< offsend managed\n";
        let pats = ManagedIgnoreBlock::patterns(contents, None).unwrap();
        assert_eq!(pats, vec![".env".to_string(), "*.pem".to_string()]);
    }
}
