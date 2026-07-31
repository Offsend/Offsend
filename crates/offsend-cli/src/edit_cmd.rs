//! `edit` — open the project configuration in the configured text editor.

use clap::Args;
use offsend_policy::CONFIG_FILENAME;
use std::path::PathBuf;
use std::process::{Command, ExitCode};

#[derive(Debug, Args)]
pub struct EditArgs {
    /// Project directory. Defaults to the current directory.
    #[arg(long)]
    pub path: Option<String>,
}

pub fn run(args: EditArgs) -> Result<ExitCode, String> {
    let root = args
        .path
        .map(PathBuf::from)
        .unwrap_or_else(|| std::env::current_dir().unwrap_or_else(|_| PathBuf::from(".")));
    let config = root.join(CONFIG_FILENAME);
    if !config.is_file() {
        return Err(format!(
            "No {CONFIG_FILENAME} at {}. Run `offsend init` first.",
            config.display()
        ));
    }

    let editor = std::env::var("VISUAL")
        .ok()
        .filter(|value| !value.is_empty())
        .or_else(|| {
            std::env::var("EDITOR")
                .ok()
                .filter(|value| !value.is_empty())
        });
    let status = if let Some(editor) = editor {
        // $EDITOR may contain arguments (e.g. "code --wait"); run via the shell.
        Command::new("sh")
            .arg("-c")
            .arg(format!("{editor} \"$1\""))
            .arg("sh")
            .arg(&config)
            .status()
    } else {
        #[cfg(target_os = "macos")]
        {
            Command::new("open").arg("-t").arg(&config).status()
        }
        #[cfg(not(target_os = "macos"))]
        {
            return Err(format!(
                "Set $EDITOR or $VISUAL to edit {CONFIG_FILENAME}."
            ));
        }
    }
    .map_err(|error| format!("Failed to open {}: {error}", config.display()))?;

    Ok(ExitCode::from(status.code().unwrap_or(1) as u8))
}
