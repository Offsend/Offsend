//! `sync` — materialize ignore files from `.offsend.yml` and install hooks.

use clap::Args;
use offsend_policy::{IgnoreSyncService, OffsendProjectConfig, CONFIG_FILENAME};
use serde::Serialize;
use std::path::PathBuf;
use std::process::ExitCode;
use thiserror::Error;

#[derive(Debug, Args)]
pub struct SyncArgs {
    /// Project directory. Defaults to the current directory.
    #[arg(long)]
    pub path: Option<String>,

    /// Only materialize ignore files; skip hook installation.
    #[arg(long = "no-hooks", default_value_t = false)]
    pub no_hooks: bool,

    /// Show what would change without writing. Hooks are not installed.
    #[arg(long, default_value_t = false)]
    pub dry_run: bool,

    /// Output format (text, json).
    #[arg(long, default_value = "text")]
    pub format: String,
}

#[derive(Debug, Error)]
pub enum SyncError {
    #[error("{0}")]
    Message(String),
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct JsonReport {
    directory: String,
    dry_run: bool,
    patterns: Vec<String>,
    commit_ignore_files: bool,
    created_relative_paths: Vec<String>,
    updated_relative_paths: Vec<String>,
    unchanged_relative_paths: Vec<String>,
    gitignore_updated: bool,
    gitignore_path: Option<String>,
    exclude_updated: bool,
    exclude_path: Option<String>,
    errors: Vec<String>,
    hooks: HooksJson,
    sandbox: SandboxJson,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct HooksJson {
    skipped: bool,
    reason: String,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct SandboxJson {
    enabled: bool,
    changes: Vec<SandboxChangeJson>,
    uncovered_patterns: Vec<String>,
    manual_steps: Vec<String>,
    errors: Vec<String>,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct SandboxChangeJson {
    relative_path: String,
    kind: String,
    mechanism: String,
}

pub fn run(args: SyncArgs) -> Result<ExitCode, SyncError> {
    let format = match args.format.as_str() {
        "text" => Format::Text,
        "json" => Format::Json,
        other => {
            return Err(SyncError::Message(format!(
                "Invalid --format value: {other}. Expected one of: text, json."
            )))
        }
    };

    let directory = args
        .path
        .map(PathBuf::from)
        .unwrap_or_else(|| std::env::current_dir().unwrap_or_else(|_| PathBuf::from(".")));

    let report = IgnoreSyncService::run(&directory, args.dry_run);
    let config = OffsendProjectConfig::load_from_path(&report.directory_path.join(CONFIG_FILENAME))
        .ok()
        .flatten();
    let sandbox = crate::sandbox_sync::run_targets(
        &report.directory_path,
        config.as_ref(),
        &crate::sandbox_sync::default_targets(),
        args.dry_run,
    );

    let (hooks_skipped, hooks_reason) = if args.dry_run {
        (true, "dry-run".to_string())
    } else if args.no_hooks {
        (true, "--no-hooks".to_string())
    } else if !crate::hook_policy::should_install(config.as_ref()) {
        (true, "hooks.enabled is false".to_string())
    } else if report.has_errors() {
        (true, "ignore sync failed".to_string())
    } else {
        match crate::hook_cmd::install_for_sync(&report.directory_path, config.as_ref(), false, false)
        {
            Ok(()) => (false, "installed".to_string()),
            Err(e) => {
                eprintln!("warning: hooks: {e}");
                (true, format!("hook install failed: {e}"))
            }
        }
    };

    match format {
        Format::Text => {
            for p in &report.created_relative_paths {
                println!("created {p}");
            }
            for p in &report.updated_relative_paths {
                println!("updated {p}");
            }
            if report.gitignore_updated {
                if let Some(path) = &report.gitignore_path {
                    println!("updated {}", path.display());
                }
            }
            if report.exclude_updated {
                if let Some(path) = &report.exclude_path {
                    println!("updated {}", path.display());
                }
            }
            for err in &report.errors {
                eprintln!("error: {err}");
            }
            for change in &sandbox.changes {
                if change.kind != crate::sandbox_sync::ChangeKind::Unchanged {
                    println!("sandbox {} {}", change.kind.as_str(), change.relative_path);
                }
            }
            for pattern in &sandbox.uncovered_patterns {
                eprintln!("sandbox uncovered: {pattern}");
            }
            for step in &sandbox.manual_steps {
                eprintln!("sandbox hint: {step}");
            }
            for error in &sandbox.errors {
                eprintln!("sandbox error: {error}");
            }
            if !report.dry_run
                && report.created_relative_paths.is_empty()
                && report.updated_relative_paths.is_empty()
                && !report.gitignore_updated
                && !report.exclude_updated
                && report.errors.is_empty()
            {
                eprintln!(
                    "unchanged ({} ignore file(s))",
                    report.unchanged_relative_paths.len()
                );
            }
            if hooks_skipped {
                eprintln!("hooks: skipped ({hooks_reason})");
            } else {
                eprintln!("hooks: {hooks_reason}");
            }
        }
        Format::Json => {
            let payload = JsonReport {
                directory: report.directory_path.display().to_string(),
                dry_run: report.dry_run,
                patterns: report.patterns.clone(),
                commit_ignore_files: report.commit_ignore_files,
                created_relative_paths: report.created_relative_paths.clone(),
                updated_relative_paths: report.updated_relative_paths.clone(),
                unchanged_relative_paths: report.unchanged_relative_paths.clone(),
                gitignore_updated: report.gitignore_updated,
                gitignore_path: report
                    .gitignore_path
                    .as_ref()
                    .map(|p| p.display().to_string()),
                exclude_updated: report.exclude_updated,
                exclude_path: report
                    .exclude_path
                    .as_ref()
                    .map(|p| p.display().to_string()),
                errors: report.errors.clone(),
                hooks: HooksJson {
                    skipped: hooks_skipped,
                    reason: hooks_reason,
                },
                sandbox: SandboxJson {
                    enabled: sandbox.enabled,
                    changes: sandbox
                        .changes
                        .iter()
                        .map(|change| SandboxChangeJson {
                            relative_path: change.relative_path.clone(),
                            kind: change.kind.as_str().into(),
                            mechanism: change.mechanism.as_str().into(),
                        })
                        .collect(),
                    uncovered_patterns: sandbox.uncovered_patterns.clone(),
                    manual_steps: sandbox.manual_steps.clone(),
                    errors: sandbox.errors.clone(),
                },
            };
            println!(
                "{}",
                serde_json::to_string_pretty(&payload)
                    .map_err(|e| SyncError::Message(e.to_string()))?
            );
        }
    }

    Ok(if report.has_errors() || !sandbox.errors.is_empty() {
        ExitCode::from(2)
    } else {
        ExitCode::SUCCESS
    })
}

enum Format {
    Text,
    Json,
}
