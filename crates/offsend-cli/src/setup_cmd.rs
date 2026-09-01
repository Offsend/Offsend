//! `setup` — one-time machine install: seal key + user-level editor hooks.

use clap::Args;
use std::process::ExitCode;

#[derive(Debug, Args)]
pub struct SetupArgs {
    /// Print what would happen without writing.
    #[arg(long, default_value_t = false)]
    pub dry_run: bool,
}

pub fn run(args: SetupArgs) -> Result<ExitCode, String> {
    let key_path = crate::keys::default_key_path();
    let has_key = key_path.is_file() || std::env::var_os(crate::keys::ENV_VAR).is_some();
    let cli = crate::hook_cmd::current_exe().unwrap_or_else(|_| "offsend".into());

    if args.dry_run {
        if has_key {
            println!("seal key: present ({})", key_path.display());
        } else {
            println!("seal key: would create {}", key_path.display());
        }
        println!("user hooks: would install cursor + claude under $HOME");
        return Ok(ExitCode::SUCCESS);
    }

    if has_key {
        println!("seal key already present ({})", key_path.display());
    } else {
        crate::seal_cmd::run_keygen(crate::seal_cmd::KeygenArgs {
            output: None,
            install_default: true,
            name: None,
            force: false,
            raw: false,
            working_directory: None,
        })
        .map_err(|e| e.to_string())?;
    }

    for (name, path) in crate::hook_cmd::install_user_hooks(&cli, "soft-block")? {
        println!("installed {name} user hook ({})", path.display());
    }
    println!("setup complete — agents in any folder use machine seal defaults");
    crate::try_hint::print_post_install();
    Ok(ExitCode::SUCCESS)
}
