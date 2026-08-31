//! Built-in exclude presets for `offsend init --template`.
//! Port of Swift `ProjectConfigTemplates` / `ProjectConfigTemplateID`.

use crate::template::DEFAULT_IGNORE_PATTERNS;
use std::collections::{HashMap, HashSet};

/// Template IDs accepted by `--template`.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum TemplateId {
    Common,
    Node,
    Python,
    Go,
    Rust,
    Ruby,
    Java,
    Android,
    Swift,
    Tuist,
}

impl TemplateId {
    pub const ALL: &'static [TemplateId] = &[
        TemplateId::Common,
        TemplateId::Node,
        TemplateId::Python,
        TemplateId::Go,
        TemplateId::Rust,
        TemplateId::Ruby,
        TemplateId::Java,
        TemplateId::Android,
        TemplateId::Swift,
        TemplateId::Tuist,
    ];

    pub fn as_str(self) -> &'static str {
        match self {
            TemplateId::Common => "common",
            TemplateId::Node => "node",
            TemplateId::Python => "python",
            TemplateId::Go => "go",
            TemplateId::Rust => "rust",
            TemplateId::Ruby => "ruby",
            TemplateId::Java => "java",
            TemplateId::Android => "android",
            TemplateId::Swift => "swift",
            TemplateId::Tuist => "tuist",
        }
    }

    pub fn summary(self) -> &'static str {
        match self {
            TemplateId::Common => {
                "Lockfiles, OS junk, dist/build/coverage, minified/maps, linter caches, .offsend/hooks"
            }
            TemplateId::Node => {
                "node_modules, lockfiles, bundler/Storybook caches, Next/Nuxt/Turbo/Vercel"
            }
            TemplateId::Python => {
                "venvs, __pycache__, mypy/pytest/ruff caches, egg-info, Jupyter checkpoints"
            }
            TemplateId::Go => "vendor/, go.sum",
            TemplateId::Rust => "target/",
            TemplateId::Ruby => "vendor/bundle, .bundle",
            TemplateId::Java => ".gradle, Maven/IDEA out and target, class/jar",
            TemplateId::Android => "NDK/CXX build dirs, APK/AAB/DEX/class/jar artifacts",
            TemplateId::Swift => {
                "DerivedData, SPM .build/Package.resolved, Pods, Carthage, archives"
            }
            TemplateId::Tuist => "Derived/, Tuist build/dependencies, .package.resolved",
        }
    }

    pub fn exclude_patterns(self) -> &'static [&'static str] {
        match self {
            TemplateId::Common => &[
                "*.lock",
                ".DS_Store",
                "Thumbs.db",
                "Desktop.ini",
                "**/dist/**",
                "**/build/**",
                "**/coverage/**",
                "*.map",
                "*.min.js",
                "*.min.css",
                ".eslintcache",
                ".stylelintcache",
                ".offsend/hooks/**",
                "**/*.png",
                "**/*.gif",
                "**/*.jpg",
                "**/*.jpeg",
                "**/*.ico",
                "**/*.webp",
                "**/*.icns",
            ],
            TemplateId::Node => &[
                "**/node_modules/**",
                "**/.next/**",
                "**/.nuxt/**",
                "**/.output/**",
                "**/.turbo/**",
                "**/.vercel/**",
                "**/bower_components/**",
                "**/.yarn/cache/**",
                "**/.yarn/unplugged/**",
                "**/.pnpm-store/**",
                "**/.svelte-kit/**",
                "**/.parcel-cache/**",
                "**/.vite/**",
                "**/storybook-static/**",
                "package-lock.json",
                "npm-shrinkwrap.json",
                "pnpm-lock.yaml",
                "bun.lock",
                "bun.lockb",
                "install-state.gz",
                "*.tsbuildinfo",
            ],
            TemplateId::Python => &[
                "**/.venv/**",
                "**/venv/**",
                "**/__pycache__/**",
                "**/.mypy_cache/**",
                "**/.pytest_cache/**",
                "**/.ruff_cache/**",
                "**/*.egg-info/**",
                "**/.tox/**",
                "**/.eggs/**",
                "**/.nox/**",
                "**/htmlcov/**",
                "**/.ipynb_checkpoints/**",
                "*.pyc",
                "*.pyo",
            ],
            TemplateId::Go => &["**/vendor/**", "go.sum"],
            TemplateId::Rust => &["**/target/**"],
            TemplateId::Ruby => &["**/vendor/bundle/**", "**/.bundle/**"],
            TemplateId::Java => &[
                "**/.gradle/**",
                "**/out/**",
                "**/.idea/**",
                "**/target/**",
                "*.class",
                "*.jar",
            ],
            TemplateId::Android => &[
                "**/.cxx/**",
                "**/.externalNativeBuild/**",
                "*.apk",
                "*.aab",
                "*.dex",
                "*.class",
                "*.jar",
            ],
            TemplateId::Swift => &[
                "**/DerivedData/**",
                "**/.build/**",
                "**/Pods/**",
                "**/Carthage/Build/**",
                "**/xcuserdata/**",
                "*.xcuserstate",
                "*.xcarchive/**",
                "Package.resolved",
                "*.ipa",
                "**/*.dSYM/**",
            ],
            TemplateId::Tuist => &[
                "**/Derived/**",
                "**/Tuist/.build/**",
                "**/Tuist/Dependencies/**",
                "**/.tuist-bin/**",
                "**/.tuist-generated",
                ".package.resolved",
            ],
        }
    }

    fn from_raw(key: &str) -> Option<Self> {
        match key {
            "common" => Some(TemplateId::Common),
            "node" => Some(TemplateId::Node),
            "python" => Some(TemplateId::Python),
            "go" => Some(TemplateId::Go),
            "rust" => Some(TemplateId::Rust),
            "ruby" => Some(TemplateId::Ruby),
            "java" => Some(TemplateId::Java),
            "android" => Some(TemplateId::Android),
            "swift" => Some(TemplateId::Swift),
            "tuist" => Some(TemplateId::Tuist),
            _ => None,
        }
    }
}

/// Optional patterns kept as YAML comments in starter configs (not active excludes).
pub static COMMENTED_OPTIONAL_EXCLUDE_PATTERNS: &[&str] =
    &["**/.cache/**", "**/tmp/**", "**/temp/**"];

/// Aliases accepted by `--template` (resolved case-insensitively).
pub static TEMPLATE_ALIASES: &[(&str, TemplateId)] = &[
    ("js", TemplateId::Node),
    ("ts", TemplateId::Node),
    ("javascript", TemplateId::Node),
    ("typescript", TemplateId::Node),
    ("ios", TemplateId::Swift),
];

/// Detectors disabled by `offsend init` — PII/noise only.
pub static DEFAULT_DISABLED_DETECTOR_IDS: &[&str] = &[
    "email",
    "phone",
    "money",
    "url",
    "ipAddress",
    "internalDomain",
    "contractId",
    "invoiceId",
    "orderId",
    "creditCardLike",
    "iban",
    "personName",
    "streetAddress",
    "governmentId",
];

/// Built-in secret/credential detector IDs that must remain enabled in init defaults.
pub static CREDENTIAL_DETECTOR_IDS: &[&str] = &[
    "apiKeyGeneric",
    "openAIAPIKey",
    "awsAccessKeyId",
    "githubToken",
    "slackToken",
    "stripeKey",
    "jwt",
    "privateKey",
    "sshPrivateKey",
    "databaseURLWithPassword",
    "bearerToken",
    "highEntropyString",
];

fn known_templates_csv() -> String {
    TemplateId::ALL
        .iter()
        .map(|id| id.as_str())
        .collect::<Vec<_>>()
        .join(", ")
}

/// Parses a single template id or alias (case-insensitive).
pub fn parse_template_id(raw: &str) -> Result<TemplateId, String> {
    let key = raw.trim().to_ascii_lowercase();
    if let Some(id) = TemplateId::from_raw(&key) {
        return Ok(id);
    }
    if let Some((_, id)) = TEMPLATE_ALIASES.iter().find(|(alias, _)| *alias == key) {
        return Ok(*id);
    }
    Err(format!(
        "Unknown template '{}'. Known templates: {}.",
        raw,
        known_templates_csv()
    ))
}

/// Parses repeated `--template` values and CSV fragments (`node,swift`).
/// Case-insensitive; supports aliases. Always includes `common` first.
pub fn resolve(raw_values: &[String]) -> Result<Vec<TemplateId>, String> {
    let mut resolved = vec![TemplateId::Common];
    let mut seen = HashSet::from([TemplateId::Common]);

    for raw in raw_values {
        for part in raw.split(',') {
            let part = part.trim();
            if part.is_empty() {
                continue;
            }
            let id = parse_template_id(part)?;
            if seen.insert(id) {
                resolved.push(id);
            }
        }
    }

    Ok(resolved)
}

/// Union of exclude patterns for the given templates, preserving order and deduping.
/// Inserts `common` if missing.
pub fn exclude_patterns(ids: &[TemplateId]) -> Vec<String> {
    let mut ordered = ids.to_vec();
    if !ordered.contains(&TemplateId::Common) {
        ordered.insert(0, TemplateId::Common);
    }

    let mut patterns = Vec::new();
    let mut seen = HashSet::new();
    for id in ordered {
        for pattern in id.exclude_patterns() {
            if seen.insert(*pattern) {
                patterns.push((*pattern).to_string());
            }
        }
    }
    patterns
}

/// Merges `additional` into `existing`, preserving existing order and appending new patterns.
pub fn merge_exclude_lists(
    existing: &[String],
    additional: &[String],
) -> (Vec<String>, Vec<String>) {
    let mut merged = existing.to_vec();
    let mut seen: HashSet<String> = existing.iter().cloned().collect();
    let mut added = Vec::new();
    for pattern in additional {
        if seen.insert(pattern.clone()) {
            merged.push(pattern.clone());
            added.push(pattern.clone());
        }
    }
    (merged, added)
}

fn parse_yaml_list_item(trimmed: &str) -> String {
    let mut value = trimmed.trim();
    if let Some(rest) = value.strip_prefix('-') {
        value = rest.trim();
    }
    if value.len() >= 2 {
        if (value.starts_with('"') && value.ends_with('"'))
            || (value.starts_with('\'') && value.ends_with('\''))
        {
            value = &value[1..value.len() - 1];
        }
    }
    value.to_string()
}

fn render_exclude_block(patterns: &[String]) -> String {
    if patterns.is_empty() {
        return "  exclude: []".to_string();
    }
    let items = patterns
        .iter()
        .map(|p| format!("    - \"{p}\""))
        .collect::<Vec<_>>()
        .join("\n");
    format!("  exclude:\n{items}")
}

/// Updates the `check.exclude` list in an existing YAML document, preserving surrounding content
/// when an `exclude:` block is already present.
pub fn merging_exclude(yaml: &str, patterns: &[String]) -> Result<(String, Vec<String>), String> {
    let lines: Vec<&str> = yaml.split('\n').collect();
    let mut existing: Vec<String> = Vec::new();
    let mut exclude_line_index: Option<usize> = None;
    let mut list_start: Option<usize> = None;
    let mut list_end: Option<usize> = None;

    for (index, line) in lines.iter().enumerate() {
        let trimmed = line.trim();
        if trimmed.starts_with("exclude:") {
            exclude_line_index = Some(index);
            let inline = trimmed["exclude:".len()..].trim();
            if inline == "[]" {
                list_start = Some(index + 1);
                list_end = Some(index);
            } else if inline.starts_with('-') {
                list_start = Some(index + 1);
                list_end = Some(index);
            } else {
                list_start = Some(index + 1);
                let mut end = index;
                for j in (index + 1)..lines.len() {
                    let item = lines[j].trim();
                    if item.starts_with('-') {
                        existing.push(parse_yaml_list_item(item));
                        end = j;
                    } else if item.is_empty() || item.starts_with('#') {
                        continue;
                    } else {
                        break;
                    }
                }
                list_end = Some(end);
            }
            break;
        }
    }

    let (merged, added) = merge_exclude_lists(&existing, patterns);
    let exclude_block = render_exclude_block(&merged);

    let (Some(exclude_line_index), Some(_list_start), Some(list_end)) =
        (exclude_line_index, list_start, list_end)
    else {
        if let Some(check_index) = lines.iter().position(|line| {
            let t = line.trim();
            t == "check:" || t.starts_with("check:")
        }) {
            let mut new_lines: Vec<String> = lines.iter().map(|s| (*s).to_string()).collect();
            let insertion: Vec<String> = exclude_block.split('\n').map(|s| s.to_string()).collect();
            let insert_at = check_index + 1;
            new_lines.splice(insert_at..insert_at, insertion);
            return Ok((new_lines.join("\n"), added));
        }
        let mut new_lines: Vec<String> = lines.iter().map(|s| (*s).to_string()).collect();
        if new_lines.last().is_some_and(|l| l.is_empty()) {
            new_lines.pop();
        }
        new_lines.push("check:".to_string());
        new_lines.extend(exclude_block.split('\n').map(|s| s.to_string()));
        new_lines.push(String::new());
        return Ok((new_lines.join("\n"), added));
    };

    let mut new_lines: Vec<String> = lines[..exclude_line_index]
        .iter()
        .map(|s| (*s).to_string())
        .collect();
    new_lines.extend(exclude_block.split('\n').map(|s| s.to_string()));
    if list_end + 1 < lines.len() {
        new_lines.extend(lines[list_end + 1..].iter().map(|s| (*s).to_string()));
    }
    let mut result = new_lines.join("\n");
    if !result.ends_with('\n') {
        result.push('\n');
    }
    Ok((result, added))
}

fn render_ignore_section(commit: bool, patterns: &[&str]) -> String {
    let commit_val = if commit { "true" } else { "false" };
    let patterns_block = if patterns.is_empty() {
        "  patterns: []".to_string()
    } else {
        let items = patterns
            .iter()
            .map(|p| format!("    - \"{p}\""))
            .collect::<Vec<_>>()
            .join("\n");
        format!("  patterns:\n{items}")
    };
    format!("ignore:\n  commit: {commit_val}\n{patterns_block}")
}

/// Full starter `.offsend.yml` contents for `offsend init`.
pub fn render_yaml(
    templates: &[TemplateId],
    ignore_commit: bool,
    hooks_publish: bool,
    strict_credentials: bool,
) -> String {
    let ids: Vec<TemplateId> = if templates.contains(&TemplateId::Common) {
        templates.to_vec()
    } else {
        let mut v = vec![TemplateId::Common];
        v.extend_from_slice(templates);
        v
    };
    let labels = ids
        .iter()
        .map(|id| id.as_str())
        .collect::<Vec<_>>()
        .join(", ");

    let extras: Vec<&str> = ids
        .iter()
        .filter(|id| **id != TemplateId::Common)
        .map(|id| id.as_str())
        .collect();
    let mut generated_parts = Vec::new();
    if extras.is_empty() {
        generated_parts.push("offsend init".to_string());
    } else {
        generated_parts.push(format!("offsend init --template {}", extras.join(",")));
    }
    if strict_credentials {
        generated_parts.push("--strict-credentials".to_string());
    }
    let generated_by = generated_parts.join(" ");

    let patterns = exclude_patterns(&ids);
    let exclude_lines = patterns
        .iter()
        .map(|p| format!("    - \"{p}\""))
        .collect::<Vec<_>>()
        .join("\n");
    let ignore_section = render_ignore_section(ignore_commit, DEFAULT_IGNORE_PATTERNS);
    let hooks_publish_line = format!(
        "  publish: {}",
        if hooks_publish { "true" } else { "false" }
    );
    let disable_lines = DEFAULT_DISABLED_DETECTOR_IDS
        .iter()
        .map(|id| format!("      - {id}"))
        .collect::<Vec<_>>()
        .join("\n");
    let context_section = if strict_credentials {
        r#"
# Strict credentials: tighter MCP/subagent/history. Prompt hooks stay
# soft-block unless: offsend hook install --hook-policy block
context:
  read:
    on_secret: seal
  mcp:
    responses: seal
    mode: ask
  subagents:
    mode: deny
    scan_task: true
  history:
    audit: true
"#
    } else {
        r#"
context:
  read:
    on_secret: seal
  mcp:
    responses: seal
"#
    };

    format!(
        r#"version: 1

check:
  fail_on: block
  policy: true
  # Generated by: {generated_by}
  # templates: {labels}
  exclude:
{exclude_lines}
  detectors:
    disable:
{disable_lines}

{ignore_section}

hooks:
  enabled: true
  git: [pre-commit, post-merge]
  fail_on: block
  policy: true
{hooks_publish_line}
{context_section}"#
    )
}

/// Human-readable catalog for `--list-templates`.
pub fn list_templates_text() -> String {
    let mut lines = vec![
        "Available exclude templates (`common` is always included):".to_string(),
        String::new(),
    ];

    let mut alias_by_id: HashMap<TemplateId, Vec<&str>> = HashMap::new();
    let mut alias_keys: Vec<&str> = TEMPLATE_ALIASES.iter().map(|(a, _)| *a).collect();
    alias_keys.sort_unstable();
    for key in alias_keys {
        if let Some((_, id)) = TEMPLATE_ALIASES.iter().find(|(a, _)| *a == key) {
            alias_by_id.entry(*id).or_default().push(key);
        }
    }
    for names in alias_by_id.values_mut() {
        names.sort_unstable();
    }

    for id in TemplateId::ALL {
        let mut line = format!("  {}  — {}", id.as_str(), id.summary());
        if let Some(names) = alias_by_id.get(id) {
            if !names.is_empty() {
                line.push_str(&format!(" (aliases: {})", names.join(", ")));
            }
        }
        lines.push(line);
    }
    lines.push(String::new());
    lines.push("Examples:".to_string());
    lines.push("  offsend init --template node".to_string());
    lines.push("  offsend init --template js,swift".to_string());
    lines.push("  offsend init --template python --merge-exclude".to_string());
    lines.join("\n")
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::OffsendProjectConfig;

    #[test]
    fn resolve_aliases_and_case_insensitive() {
        let ids = resolve(&[
            "JS".to_string(),
            "ios".to_string(),
            "TypeScript".to_string(),
        ])
        .unwrap();
        assert_eq!(
            ids,
            vec![TemplateId::Common, TemplateId::Node, TemplateId::Swift]
        );
    }

    #[test]
    fn resolve_csv_and_dedupe() {
        let ids = resolve(&[
            "node,swift".to_string(),
            "swift".to_string(),
            "tuist".to_string(),
        ])
        .unwrap();
        assert_eq!(
            ids,
            vec![
                TemplateId::Common,
                TemplateId::Node,
                TemplateId::Swift,
                TemplateId::Tuist
            ]
        );
    }

    #[test]
    fn resolve_empty_is_common_only() {
        let ids = resolve(&[]).unwrap();
        assert_eq!(ids, vec![TemplateId::Common]);
    }

    #[test]
    fn resolve_unknown_errors() {
        let err = resolve(&["nodejs".to_string()]).unwrap_err();
        assert!(err.contains("Unknown template 'nodejs'"));
        assert!(err.contains("common"));
    }

    #[test]
    fn merge_exclude_preserves_order_and_reports_added() {
        let existing = vec!["*.lock".to_string(), "custom/**".to_string()];
        let additional = vec![
            "**/node_modules/**".to_string(),
            "*.lock".to_string(),
            "**/dist/**".to_string(),
        ];
        let (merged, added) = merge_exclude_lists(&existing, &additional);
        assert_eq!(
            merged,
            vec![
                "*.lock".to_string(),
                "custom/**".to_string(),
                "**/node_modules/**".to_string(),
                "**/dist/**".to_string(),
            ]
        );
        assert_eq!(
            added,
            vec!["**/node_modules/**".to_string(), "**/dist/**".to_string(),]
        );
    }

    #[test]
    fn render_yaml_contains_exclude_patterns() {
        let yaml = render_yaml(&[TemplateId::Node], false, false, false);
        assert!(yaml.contains("**/node_modules/**"));
        assert!(yaml.contains("*.lock"));
        assert!(yaml.contains("# templates: common, node"));
        assert!(yaml.contains("ignore:"));
        assert!(yaml.contains("commit: false"));
        assert!(yaml.contains("publish: false"));
        assert!(yaml.contains("enabled: true"));
        assert!(yaml.contains("git: [pre-commit, post-merge]"));
        assert!(yaml.contains("policy: true"));
        assert!(!yaml.contains("policy: false"));
        assert!(yaml.contains("on_secret: seal"));
        assert!(yaml.contains("responses: seal"));
        assert!(!yaml.contains("All detector IDs"));
        assert!(!yaml.contains("dictionaries:"));
        assert!(yaml.contains(".env*"));
        assert!(yaml.contains("*.pem"));
        OffsendProjectConfig::parse_yaml(&yaml).expect("init YAML must parse");
    }

    #[test]
    fn render_yaml_strict_credentials() {
        let yaml = render_yaml(&[TemplateId::Node], false, false, true);
        assert!(yaml.contains("--strict-credentials"));
        assert!(yaml.contains("policy: true"));
        assert!(yaml.contains("on_secret: seal"));
        assert!(yaml.contains("responses: seal"));
        assert!(yaml.contains("mode: ask"));
        assert!(yaml.contains("mode: deny"));
        assert!(yaml.contains("scan_task: true"));
        assert!(yaml.contains("audit: true"));
        OffsendProjectConfig::parse_yaml(&yaml).expect("strict init YAML must parse");
    }

    #[test]
    fn merging_exclude_into_existing_yaml() {
        let existing = r#"version: 1

check:
  fail_on: block
  exclude:
    - "*.lock"
    - "custom/**"
  detectors:
    disable:
      - email

hooks:
  git: [pre-commit]
"#;
        let (yaml, added) = merging_exclude(
            existing,
            &[
                "**/node_modules/**".to_string(),
                "*.lock".to_string(),
                "**/dist/**".to_string(),
            ],
        )
        .unwrap();
        assert_eq!(
            added,
            vec!["**/node_modules/**".to_string(), "**/dist/**".to_string(),]
        );
        assert!(yaml.contains("custom/**"));
        assert!(yaml.contains("**/node_modules/**"));
        assert!(yaml.contains("detectors:"));
        assert!(yaml.contains("- email"));
    }
}
