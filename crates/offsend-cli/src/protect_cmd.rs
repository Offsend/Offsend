//! `protect` — create missing AI ignore/rule files and promote exposure patterns.

use clap::Args;
use offsend_policy::{
    claude_privacy_rule_contents, cursor_privacy_rule_contents, default_audit_configuration,
    IgnoreSyncService, OffsendProjectConfig, PrivacyAuditor, RuleSeverity, CONFIG_FILENAME,
};
use serde::Serialize;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::ExitCode;

#[derive(Debug, Args)]
pub struct ProtectArgs {
    #[arg(long)]
    pub path: Option<String>,

    #[arg(long, default_value_t = false)]
    pub dry_run: bool,

    /// Also promote recommended (not only required) exposure patterns.
    #[arg(long = "include-recommended", default_value_t = false)]
    pub include_recommended: bool,

    /// Output format (text, json).
    #[arg(long, default_value = "text")]
    pub format: String,
}

#[derive(Serialize)]
struct ProtectReport {
    dry_run: bool,
    promoted: Vec<String>,
    created: Vec<String>,
    updated: Vec<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    history_scrub: Option<HistoryScrubJson>,
    errors: Vec<String>,
}

#[derive(Serialize)]
struct HistoryScrubJson {
    dry_run: bool,
    files_touched: usize,
    redaction_count: usize,
    errors: Vec<String>,
}

pub fn run(args: ProtectArgs) -> Result<ExitCode, String> {
    let format = match args.format.as_str() {
        "text" => Format::Text,
        "json" => Format::Json,
        other => {
            return Err(format!(
                "Invalid --format value: {other}. Expected text or json."
            ))
        }
    };

    let dir = args
        .path
        .map(PathBuf::from)
        .unwrap_or_else(|| std::env::current_dir().unwrap_or_else(|_| PathBuf::from(".")));
    let root = crate::hook_git::resolve_repo_root(&dir).unwrap_or(dir);
    let mut errors = Vec::new();
    let mut created = Vec::new();
    let mut updated = Vec::new();

    // 1) Create missing keepManagedContent rule files.
    let cfg = default_audit_configuration();
    for rule in &cfg.rules {
        let Some(fix) = &rule.fix else { continue };
        if fix.strategy != offsend_policy::FixStrategy::KeepManagedContent {
            continue;
        }
        let path = root.join(&fix.relative_path);
        let desired = if fix.relative_path.ends_with(".mdc") {
            cursor_privacy_rule_contents()
        } else if fix.relative_path.ends_with(".md") {
            claude_privacy_rule_contents()
        } else {
            fix.contents.clone()
        };
        if path.is_file() {
            let existing = fs::read_to_string(&path).unwrap_or_default();
            if existing == desired {
                continue;
            }
            match write_or_preview(&path, &desired, args.dry_run) {
                Ok(true) => {
                    let rel = fix.relative_path.clone();
                    updated.push(rel.clone());
                    if format == Format::Text {
                        println!(
                            "{} {rel}",
                            if args.dry_run {
                                "would update"
                            } else {
                                "updated"
                            }
                        );
                    }
                }
                Ok(false) => {}
                Err(e) => errors.push(e),
            }
        } else {
            match write_or_preview(&path, &desired, args.dry_run) {
                Ok(true) => {
                    let rel = fix.relative_path.clone();
                    created.push(rel.clone());
                    if format == Format::Text {
                        println!(
                            "{} {rel}",
                            if args.dry_run {
                                "would create"
                            } else {
                                "created"
                            }
                        );
                    }
                }
                Ok(false) => {}
                Err(e) => errors.push(e),
            }
        }
    }

    // 2) Ensure .offsend.yml exists for promote/sync.
    let config_path = root.join(CONFIG_FILENAME);
    if !config_path.is_file() {
        return Err(format!(
            "No {CONFIG_FILENAME} in {}. Run `offsend init` first.",
            root.display()
        ));
    }

    let project_config = OffsendProjectConfig::load_from_path(&config_path)
        .map_err(|e| e.to_string())?
        .ok_or_else(|| format!("No {CONFIG_FILENAME} in {}.", root.display()))?;

    // 3) Audit exposures → promote sensitive pattern canonical lines into ignore.patterns.
    let audit = PrivacyAuditor::audit_with(&root, &cfg);
    let mut to_promote = Vec::new();
    for f in &audit.sensitive_pattern_findings {
        if f.is_satisfied() {
            continue;
        }
        match f.pattern.severity {
            RuleSeverity::Required => {}
            RuleSeverity::Recommended if args.include_recommended => {}
            _ => continue,
        }
        to_promote.push(f.pattern.canonical_ignore_line().to_string());
    }
    let promoted = if !to_promote.is_empty() && !args.dry_run {
        let added = crate::yaml_ignore::merge_ignore_patterns(&config_path, &to_promote)?;
        if format == Format::Text {
            for p in &added {
                println!("promoted ignore pattern: {p}");
            }
        }
        added
    } else if !to_promote.is_empty() {
        if format == Format::Text {
            for p in &to_promote {
                println!("would promote: {p}");
            }
        }
        to_promote
    } else {
        Vec::new()
    };

    // 4) Materialize ignore files.
    let report = IgnoreSyncService::run(&root, args.dry_run);
    for p in &report.created_relative_paths {
        created.push(p.clone());
        if format == Format::Text {
            println!(
                "{} {p}",
                if args.dry_run {
                    "would create"
                } else {
                    "created"
                }
            );
        }
    }
    for p in &report.updated_relative_paths {
        updated.push(p.clone());
        if format == Format::Text {
            println!(
                "{} {p}",
                if args.dry_run {
                    "would update"
                } else {
                    "updated"
                }
            );
        }
    }
    errors.extend(report.errors.clone());

    // 5) Optional history scrub when configured.
    let history_scrub = if project_config.history_scrub_on_protect() {
        let summary =
            crate::history_cmd::scrub_transcripts(Some(&root), false, !args.dry_run);
        if format == Format::Text {
            println!(
                "history scrub ({}): {} redaction(s) across {} file(s)",
                if args.dry_run { "dry-run" } else { "applied" },
                summary.redaction_count,
                summary.files_touched.len()
            );
            for error in &summary.errors {
                eprintln!("error: {error}");
            }
        }
        errors.extend(summary.errors.iter().cloned());
        Some(HistoryScrubJson {
            dry_run: summary.dry_run,
            files_touched: summary.files_touched.len(),
            redaction_count: summary.redaction_count,
            errors: summary.errors,
        })
    } else {
        None
    };

    if format == Format::Json {
        println!(
            "{}",
            serde_json::to_string_pretty(&ProtectReport {
                dry_run: args.dry_run,
                promoted,
                created,
                updated,
                history_scrub,
                errors: errors.clone(),
            })
            .map_err(|e| e.to_string())?
        );
    } else if report.has_errors() {
        for e in &report.errors {
            eprintln!("error: {e}");
        }
    }

    Ok(if errors.is_empty() {
        ExitCode::SUCCESS
    } else {
        ExitCode::from(2)
    })
}

#[derive(Clone, Copy, PartialEq, Eq)]
enum Format {
    Text,
    Json,
}

/// Returns Ok(true) when a create/update was performed (or would be in dry-run).
fn write_or_preview(path: &Path, contents: &str, dry_run: bool) -> Result<bool, String> {
    if dry_run {
        return Ok(true);
    }
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent).map_err(|e| e.to_string())?;
    }
    fs::write(path, contents).map_err(|e| e.to_string())?;
    Ok(true)
}
