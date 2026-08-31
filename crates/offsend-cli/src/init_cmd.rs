//! `init` — create `.offsend.yml`.

use clap::Args;
use offsend_policy::{
    exclude_patterns, list_templates_text, merging_exclude, render_yaml, resolve,
    IgnoreSyncService, CONFIG_FILENAME,
};
use std::fs;
use std::path::PathBuf;
use std::process::ExitCode;

#[derive(Debug, Args)]
pub struct InitArgs {
    #[arg(long)]
    pub path: Option<String>,

    #[arg(long, default_value_t = false)]
    pub force: bool,

    /// Exclude preset(s); repeatable or comma-separated.
    #[arg(long = "template", value_name = "NAME")]
    pub template: Vec<String>,

    #[arg(long = "list-templates", default_value_t = false)]
    pub list_templates: bool,

    #[arg(long = "merge-exclude", default_value_t = false)]
    pub merge_exclude: bool,

    #[arg(long = "ignore-commit", default_value_t = false)]
    pub ignore_commit: bool,

    #[arg(long = "no-ignore-commit", default_value_t = false)]
    pub no_ignore_commit: bool,

    #[arg(long = "hooks-publish", default_value_t = false)]
    pub hooks_publish: bool,

    #[arg(long = "no-hooks-publish", default_value_t = false)]
    pub no_hooks_publish: bool,

    #[arg(long = "strict-credentials", default_value_t = false)]
    pub strict_credentials: bool,

    #[arg(long = "no-sync", default_value_t = false)]
    pub no_sync: bool,

    #[arg(long = "no-check", default_value_t = false)]
    pub no_check: bool,
}

pub fn run(args: InitArgs) -> Result<ExitCode, String> {
    if args.list_templates {
        println!("{}", list_templates_text());
        return Ok(ExitCode::SUCCESS);
    }

    if args.force && args.merge_exclude {
        return Err("--force and --merge-exclude are mutually exclusive".into());
    }
    if args.ignore_commit && args.no_ignore_commit {
        return Err("--ignore-commit and --no-ignore-commit are mutually exclusive".into());
    }
    if args.hooks_publish && args.no_hooks_publish {
        return Err("--hooks-publish and --no-hooks-publish are mutually exclusive".into());
    }

    let ignore_commit = args.ignore_commit;
    let hooks_publish = args.hooks_publish;

    let dir = args
        .path
        .map(PathBuf::from)
        .unwrap_or_else(|| std::env::current_dir().unwrap_or_else(|_| PathBuf::from(".")));
    let root = crate::hook_git::resolve_repo_root(&dir).unwrap_or(dir);
    let config_path = root.join(CONFIG_FILENAME);

    let ids = resolve(&args.template)?;
    let patterns = exclude_patterns(&ids);

    if args.merge_exclude {
        if !config_path.exists() {
            return Err(format!(
                "{CONFIG_FILENAME} not found at {}. Run without --merge-exclude to create it.",
                config_path.display()
            ));
        }
        let existing = fs::read_to_string(&config_path).map_err(|e| e.to_string())?;
        let (yaml, added) = merging_exclude(&existing, &patterns)?;
        fs::write(&config_path, yaml).map_err(|e| e.to_string())?;
        println!(
            "updated {} (+{} exclude pattern{})",
            config_path.display(),
            added.len(),
            if added.len() == 1 { "" } else { "s" }
        );
    } else {
        if config_path.exists() && !args.force {
            return Err(format!(
                "{CONFIG_FILENAME} already exists at {}. Use --force to overwrite or --merge-exclude to add patterns.",
                config_path.display()
            ));
        }
        let yaml = render_yaml(&ids, ignore_commit, hooks_publish, args.strict_credentials);
        fs::write(&config_path, yaml).map_err(|e| e.to_string())?;
        println!("created {}", config_path.display());
    }

    if !args.no_sync {
        let report = IgnoreSyncService::run(&root, false);
        for p in &report.created_relative_paths {
            println!("created {p}");
        }
        for p in &report.updated_relative_paths {
            println!("updated {p}");
        }
        if report.has_errors() {
            for e in &report.errors {
                eprintln!("error: {e}");
            }
            return Ok(ExitCode::from(2));
        }
    }

    if !args.no_check {
        println!("baseline: run offsend check .");
    }
    println!("next: git add .offsend.yml && git commit -m \"Add AI context policy\"");
    println!("      offsend protect && offsend sync");
    println!("CI:");
    println!("- uses: Offsend/ai-hygiene@v1");
    println!("  with:");
    println!("    fail-on: block");
    println!("    policy: true");
    Ok(ExitCode::SUCCESS)
}
