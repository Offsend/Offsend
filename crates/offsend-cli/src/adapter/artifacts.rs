//! Executable workspace artifact classifier — port of Swift `ExecutableArtifactClassifier`.

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Enforcement {
    Deny,
    DenyWhenContentExecutable,
    Observe,
}

#[derive(Debug, Clone)]
pub struct ArtifactMatch {
    #[allow(dead_code)]
    pub path: String,
    #[allow(dead_code)]
    pub kind: &'static str,
    pub enforcement: Enforcement,
}

pub fn classify(path: &str) -> Option<ArtifactMatch> {
    let lower = path.replace('\\', "/").to_ascii_lowercase();
    let name = lower.rsplit('/').next().unwrap_or("");
    let segments: Vec<&str> = lower.split('/').filter(|s| !s.is_empty()).collect();

    if name == ".offsend.yml" {
        return Some(ArtifactMatch {
            path: path.to_string(),
            kind: "offsendPolicy",
            enforcement: Enforcement::Deny,
        });
    }

    if segments.windows(2).any(|w| w == [".cursor", "hooks.json"])
        || segments
            .windows(2)
            .any(|w| w == [".claude", "settings.json"])
        || segments
            .windows(2)
            .any(|w| w == [".claude", "settings.local.json"])
        || segments
            .windows(2)
            .any(|w| w == [".windsurf", "hooks.json"])
        || segments.windows(2).any(|w| w == [".codex", "hooks.json"])
    {
        return Some(ArtifactMatch {
            path: path.to_string(),
            kind: "editorHookConfig",
            enforcement: Enforcement::Deny,
        });
    }

    if segments.windows(2).any(|w| w == [".vscode", "tasks.json"])
        || segments.windows(2).any(|w| w == [".vscode", "launch.json"])
    {
        return Some(ArtifactMatch {
            path: path.to_string(),
            kind: "editorTaskConfig",
            enforcement: Enforcement::Deny,
        });
    }

    if segments
        .windows(2)
        .any(|w| w == [".vscode", "settings.json"])
        || name.ends_with(".code-workspace")
    {
        return Some(ArtifactMatch {
            path: path.to_string(),
            kind: "editorSettings",
            enforcement: Enforcement::DenyWhenContentExecutable,
        });
    }

    if matches!(
        name,
        ".zshrc"
            | ".zprofile"
            | ".zshenv"
            | ".bashrc"
            | ".bash_profile"
            | ".profile"
            | ".envrc"
            | ".direnvrc"
    ) || segments
        .windows(3)
        .any(|w| w == [".config", "fish", "config.fish"])
        || segments
            .windows(3)
            .any(|w| w == [".config", "direnv", "direnvrc"])
    {
        return Some(ArtifactMatch {
            path: path.to_string(),
            kind: "shellStartupConfig",
            enforcement: Enforcement::Deny,
        });
    }

    if segments.iter().any(|s| *s == ".ssh") {
        return Some(ArtifactMatch {
            path: path.to_string(),
            kind: "sshConfig",
            enforcement: Enforcement::Deny,
        });
    }

    if segments
        .iter()
        .any(|s| *s == "launchagents" || *s == "launchdaemons")
    {
        return Some(ArtifactMatch {
            path: path.to_string(),
            kind: "launchAgent",
            enforcement: Enforcement::Deny,
        });
    }

    if let Some(git_idx) = segments.iter().position(|s| *s == ".git") {
        let rest = &segments[git_idx + 1..];
        if rest.is_empty() {
            return Some(ArtifactMatch {
                path: path.to_string(),
                kind: "gitDirectoryPointer",
                enforcement: Enforcement::Deny,
            });
        }
        if rest.iter().any(|s| *s == "hooks") || name == "pre-commit" || name == "pre-push" {
            return Some(ArtifactMatch {
                path: path.to_string(),
                kind: "gitHook",
                enforcement: Enforcement::Deny,
            });
        }
        if name == "config" {
            return Some(ArtifactMatch {
                path: path.to_string(),
                kind: "gitConfig",
                enforcement: Enforcement::Deny,
            });
        }
        return Some(ArtifactMatch {
            path: path.to_string(),
            kind: "gitDirectoryPointer",
            enforcement: Enforcement::Deny,
        });
    }

    if name == ".gitconfig"
        || segments
            .windows(3)
            .any(|w| w == [".config", "git", "config"])
    {
        return Some(ArtifactMatch {
            path: path.to_string(),
            kind: "gitConfig",
            enforcement: Enforcement::Deny,
        });
    }

    if (name.ends_with(".pth") && segments.iter().any(|s| *s == "site-packages"))
        || name == "sitecustomize.py"
        || name == "usercustomize.py"
    {
        return Some(ArtifactMatch {
            path: path.to_string(),
            kind: "pythonStartupHook",
            enforcement: Enforcement::Deny,
        });
    }

    if name == "pyvenv.cfg"
        || (segments.last().is_some_and(|s| *s != name)
            && segments.windows(2).any(|w| {
                w[0] == "bin" && (w[1].starts_with("python") || w[1].starts_with("activate"))
            }))
    {
        return Some(ArtifactMatch {
            path: path.to_string(),
            kind: "virtualEnvironmentInterpreter",
            enforcement: Enforcement::Observe,
        });
    }

    // Trust store under ~/.config/offsend or Application Support/Offsend
    if segments.windows(2).any(|w| w == ["offsend", "trust"])
        || (segments.iter().any(|s| *s == "offsend")
            && segments
                .iter()
                .any(|s| s.contains("application support") || *s == ".config"))
    {
        // conservative: only exact trust-looking basenames
        if name.contains("trust")
            || name.ends_with(".json") && segments.iter().any(|s| *s == "offsend")
        {
            // skip broad match; Swift uses LocalStoreDirectory
        }
    }

    None
}

const EXECUTABLE_SETTING_MARKERS: &[&str] = &[
    "\"runtimeexecutable\"",
    "\"pythonpath\"",
    "defaultinterpreterpath",
    "interpreterpath",
    "\"shell.args\"",
    "\"terminal.integrated.env",
    "\"task.command\"",
    "\"command\":",
    "/bin/sh",
    "/bin/bash",
    "/usr/bin/env",
    "node_options",
    "pythonpath",
];

/// Heuristic: content looks like it sets interpreter / shell / task command paths.
pub fn content_looks_executable(content: &str) -> bool {
    let lower = content.to_ascii_lowercase();
    EXECUTABLE_SETTING_MARKERS.iter().any(|m| lower.contains(m))
}

/// For in-place Edit payloads: which setting key owns `old_string`?
/// Ordinary preference swaps (e.g. tabSize) must allow even when the file also
/// contains interpreter paths elsewhere.
pub fn edit_touches_executable_setting(file: &str, old_string: &str) -> bool {
    let Some(idx) = file.find(old_string) else {
        return false;
    };
    let start = idx.saturating_sub(160);
    let window = file[start..idx].to_ascii_lowercase();
    EXECUTABLE_SETTING_MARKERS.iter().any(|m| window.contains(m))
}
