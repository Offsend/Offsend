//! `ignore` — add patterns to `.offsend.yml` (or local ignore files).

use clap::Args;
use offsend_policy::{IgnoreSyncService, ManagedIgnoreBlock, CONFIG_FILENAME};
use serde_json::json;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::ExitCode;

#[derive(Debug, Args)]
pub struct IgnoreArgs {
    /// Paths or glob patterns to ignore.
    pub patterns: Vec<String>,

    #[arg(long)]
    pub path: Option<String>,

    /// Add only to local AI ignore files; do not update `.offsend.yml`.
    #[arg(long, default_value_t = false)]
    pub local: bool,

    /// Merge built-in privacy defaults into ignore.patterns.
    #[arg(long = "merge-defaults", default_value_t = false)]
    pub merge_defaults: bool,

    #[arg(long, default_value_t = false)]
    pub dry_run: bool,

    #[arg(long, default_value = "text")]
    pub format: String,
}

pub fn run(args: IgnoreArgs) -> Result<ExitCode, String> {
    if args.merge_defaults {
        if args.local {
            return Err("--merge-defaults cannot be used with --local.".into());
        }
        if !args.patterns.is_empty() {
            return Err("Do not pass patterns with --merge-defaults.".into());
        }
    } else if args.patterns.is_empty() {
        return Err(
            "Provide at least one path or pattern, or use --merge-defaults. \
             To re-materialize .offsend.yml, run `offsend sync`."
                .into(),
        );
    }

    let dir = args
        .path
        .map(PathBuf::from)
        .unwrap_or_else(|| std::env::current_dir().unwrap_or_else(|_| PathBuf::from(".")));
    let root = crate::hook_git::resolve_repo_root(&dir).unwrap_or(dir);
    let config_path = root.join(CONFIG_FILENAME);

    if args.local {
        return local_append(&root, &args.patterns, args.dry_run, &args.format);
    }

    if !config_path.is_file() {
        return Err(format!(
            "No {CONFIG_FILENAME} at {}. Run `offsend init` first.",
            config_path.display()
        ));
    }

    if args.dry_run {
        println!("would update {}", config_path.display());
    } else if args.merge_defaults {
        let added = crate::yaml_ignore::merge_default_ignore_patterns(&config_path)?;
        if added.is_empty() {
            println!("no new default patterns to merge");
        } else {
            for p in &added {
                println!("added {p}");
            }
        }
    } else {
        let added = crate::yaml_ignore::merge_ignore_patterns(&config_path, &args.patterns)?;
        if added.is_empty() {
            println!("patterns already present");
        } else {
            for p in &added {
                println!("added {p}");
            }
        }
    }

    let report = IgnoreSyncService::run(&root, args.dry_run);
    for p in &report.created_relative_paths {
        println!(
            "{} {p}",
            if args.dry_run {
                "would create"
            } else {
                "created"
            }
        );
    }
    for p in &report.updated_relative_paths {
        println!(
            "{} {p}",
            if args.dry_run {
                "would update"
            } else {
                "updated"
            }
        );
    }
    if report.has_errors() {
        for e in &report.errors {
            eprintln!("error: {e}");
        }
        return Ok(ExitCode::from(2));
    }
    Ok(ExitCode::SUCCESS)
}

fn local_append(
    root: &Path,
    patterns: &[String],
    dry_run: bool,
    format: &str,
) -> Result<ExitCode, String> {
    let normalized = normalize_local_patterns(root, patterns);
    let all_targets = IgnoreSyncService::managed_ignore_relative_paths(
        &offsend_policy::default_audit_configuration(),
        None,
    );
    let existing: Vec<String> = all_targets
        .iter()
        .filter(|rel| root.join(rel).is_file())
        .cloned()
        .collect();
    // If any AI ignore file already exists, only touch those. Otherwise create
    // the standard managed set.
    let targets: Vec<String> = if existing.is_empty() {
        all_targets
    } else {
        existing
    };

    let mut created = Vec::new();
    let mut updated = Vec::new();

    for rel in &targets {
        let path = root.join(rel);
        let existed = path.is_file();
        let existing_contents = if existed {
            fs::read_to_string(&path).ok()
        } else {
            None
        };
        let mut current = existing_contents
            .as_deref()
            .and_then(|c| ManagedIgnoreBlock::patterns(c, None))
            .unwrap_or_default();
        let mut changed = false;
        for p in &normalized {
            if !current.iter().any(|c| c == p) {
                current.push(p.clone());
                changed = true;
            }
        }
        if !changed && existed {
            continue;
        }
        let seed = existing_contents.unwrap_or_else(offsend_policy::managed_seed_contents);
        let (contents, _) = ManagedIgnoreBlock::upsert(&current, Some(&seed), None);
        if dry_run {
            if existed {
                updated.push(rel.clone());
            } else {
                created.push(rel.clone());
            }
        } else {
            if let Some(parent) = path.parent() {
                fs::create_dir_all(parent).map_err(|e| e.to_string())?;
            }
            fs::write(&path, contents).map_err(|e| e.to_string())?;
            if existed {
                updated.push(rel.clone());
            } else {
                created.push(rel.clone());
            }
        }
    }

    match format {
        "json" => {
            println!(
                "{}",
                json!({
                    "createdRelativePaths": created,
                    "updatedRelativePaths": updated,
                    "dryRun": dry_run,
                })
            );
        }
        "text" => {
            for p in &created {
                println!(
                    "{} {p}",
                    if dry_run {
                        "would create"
                    } else {
                        "created"
                    }
                );
            }
            for p in &updated {
                println!(
                    "{} {p}",
                    if dry_run {
                        "would update"
                    } else {
                        "updated"
                    }
                );
            }
        }
        other => {
            return Err(format!(
                "Invalid --format value: {other}. Expected text or json."
            ))
        }
    }
    Ok(ExitCode::SUCCESS)
}

fn normalize_local_patterns(root: &Path, patterns: &[String]) -> Vec<String> {
    let base = ManagedIgnoreBlock::normalize_patterns(patterns);
    base.into_iter()
        .map(|p| {
            if p.ends_with('/') || p.contains('*') || p.contains('?') || p.contains('[') {
                return p;
            }
            let candidate = root.join(&p);
            if candidate.is_dir() {
                format!("{p}/")
            } else {
                p
            }
        })
        .collect()
}
