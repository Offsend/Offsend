//! Sandbox provider catalog — `sandbox.<name>.yml` (shipped / global / project).

use offsend_policy::OffsendProjectConfig;
use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;
use std::fs;
use std::path::{Path, PathBuf};

pub const CATALOG_FILENAME: &str = "sandbox.yml";
const SHIPPED_CATALOG: &str = include_str!("../defaults/sandbox.yml");
const SHIPPED_NONO: &str = include_str!("../defaults/sandbox.nono.yml");

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, Default)]
#[serde(rename_all = "lowercase")]
pub enum EnsureMode {
    None,
    #[default]
    Check,
    Pull,
}

impl EnsureMode {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::None => "none",
            Self::Check => "check",
            Self::Pull => "pull",
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct PackInstall {
    /// Argv after `binary`. Placeholders: `{pack}` `{editor}` `{binary}`.
    pub args: Vec<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct PackSpec {
    pub preferred: String,
    #[serde(default)]
    pub accepted: Vec<String>,
    pub base_profile: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub ensure: Option<EnsureMode>,
}

impl PackSpec {
    pub fn accepted_or_preferred(&self) -> Vec<&str> {
        if self.accepted.is_empty() {
            vec![self.preferred.as_str()]
        } else {
            self.accepted.iter().map(String::as_str).collect()
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct SandboxProvider {
    pub name: String,
    pub binary: String,
    pub profile_directory: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub detect_env: Option<String>,
    pub run_args: Vec<String>,
    #[serde(default)]
    pub install_hint: String,
    #[serde(default = "default_pack_subdir")]
    pub pack_config_subdir: String,
    #[serde(default)]
    pub ensure: EnsureMode,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub pack_install: Option<PackInstall>,
    #[serde(default)]
    pub packs: BTreeMap<String, PackSpec>,
}

fn default_pack_subdir() -> String {
    "nono".into()
}

/// Safe project overlay — no exec-contract fields (binary / run_args / pack_install).
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
struct SafeOverlay {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    ensure: Option<EnsureMode>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    install_hint: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    packs: Option<BTreeMap<String, PackSpecOverlay>>,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
struct PackSpecOverlay {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    preferred: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    accepted: Option<Vec<String>>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    base_profile: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    ensure: Option<EnsureMode>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ProviderLayer {
    Shipped,
    Global,
    Project,
}

impl ProviderLayer {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Shipped => "shipped",
            Self::Global => "global",
            Self::Project => "project",
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ResolvedProvider {
    pub provider: SandboxProvider,
    pub id: String,
    pub layer: ProviderLayer,
    pub source_path: Option<PathBuf>,
    pub warnings: Vec<String>,
}

#[derive(Debug, Clone, Deserialize)]
struct CatalogFile {
    default_provider: String,
}

impl SandboxProvider {
    pub fn profile_relative_path(&self, editor: &str) -> String {
        format!(
            "{}/offsend-{}.json",
            self.profile_directory.trim_end_matches('/'),
            editor
        )
    }

    pub fn pack_for(&self, editor: &str) -> Option<&PackSpec> {
        self.packs.get(editor)
    }

    pub fn expand_run_args(&self, profile_relative: &str, agent: &str) -> Vec<String> {
        self.run_args
            .iter()
            .map(|part| {
                part.replace("{profile}", profile_relative)
                    .replace("{agent}", agent)
            })
            .collect()
    }

    pub fn effective_ensure(&self, editor: &str) -> EnsureMode {
        self.pack_for(editor)
            .and_then(|p| p.ensure)
            .unwrap_or(self.ensure)
    }

    pub fn pack_install_command(
        &self,
        editor: &str,
    ) -> Result<(PathBuf, Vec<String>), String> {
        let pack = self.pack_for(editor).ok_or_else(|| {
            format!("sandbox provider `{}` has no pack for `{editor}`", self.name)
        })?;
        let install = self.pack_install.as_ref().ok_or_else(|| {
            format!(
                "sandbox provider `{}` cannot install packs (no pack_install). \
                 Install manually or set ensure: check|none.",
                self.name
            )
        })?;
        if install.args.is_empty() {
            return Err(format!(
                "sandbox provider `{}`: pack_install.args is empty",
                self.name
            ));
        }
        let args = install
            .args
            .iter()
            .map(|part| {
                part.replace("{pack}", &pack.preferred)
                    .replace("{editor}", editor)
                    .replace("{binary}", &self.binary)
            })
            .collect();
        Ok((PathBuf::from(&self.binary), args))
    }

    pub fn missing_pack_message(&self, editor: &str) -> String {
        let Some(pack) = self.pack_for(editor) else {
            return format!("sandbox pack for {editor} is not configured");
        };
        let hint = match self.pack_install_command(editor) {
            Ok((bin, args)) => {
                let mut parts = vec![bin.display().to_string()];
                parts.extend(args);
                parts.join(" ")
            }
            Err(_) => format!("{} pull {}", self.binary, pack.preferred),
        };
        format!(
            "sandbox pack for {editor} is not installed (need profile `{}`). Run: {hint}",
            pack.base_profile
        )
    }

    fn apply_safe_overlay(&mut self, overlay: SafeOverlay) {
        if let Some(mode) = overlay.ensure {
            self.ensure = mode;
        }
        if let Some(hint) = overlay.install_hint {
            self.install_hint = hint;
        }
        if let Some(packs) = overlay.packs {
            for (key, ov) in packs {
                let entry = self.packs.entry(key.clone()).or_insert_with(|| PackSpec {
                    preferred: key.clone(),
                    accepted: vec![],
                    base_profile: "default".into(),
                    ensure: None,
                });
                if let Some(v) = ov.preferred.filter(|s| !s.trim().is_empty()) {
                    entry.preferred = v;
                }
                if let Some(v) = ov.accepted {
                    entry.accepted = v;
                }
                if let Some(v) = ov.base_profile.filter(|s| !s.trim().is_empty()) {
                    entry.base_profile = v;
                }
                if ov.ensure.is_some() {
                    entry.ensure = ov.ensure;
                }
            }
        }
    }
}

pub fn config_dir() -> PathBuf {
    #[cfg(target_os = "macos")]
    {
        crate::keys::home_dir().join("Library/Application Support/Offsend")
    }
    #[cfg(not(target_os = "macos"))]
    {
        std::env::var_os("XDG_CONFIG_HOME")
            .map(PathBuf::from)
            .unwrap_or_else(|| crate::keys::home_dir().join(".config"))
            .join("offsend")
    }
}

pub fn global_provider_path(id: &str) -> PathBuf {
    config_dir().join(format!("sandbox.{id}.yml"))
}

pub fn project_provider_path(root: &Path, id: &str) -> PathBuf {
    root.join(".offsend").join(format!("sandbox.{id}.yml"))
}

pub fn global_catalog_path() -> PathBuf {
    config_dir().join(CATALOG_FILENAME)
}

/// Resolve provider by catalog name.
///
/// Security:
/// - Shipped provider ids ignore project drop-ins (AI cannot override `nono` from the repo).
/// - Custom project drop-ins require a trusted policy snapshot.
/// - Overlay `ensure: none` (and per-pack none) require trust; otherwise forced to `check`.
pub fn resolve(
    project: Option<&OffsendProjectConfig>,
    project_root: Option<&Path>,
    trusted: bool,
) -> Result<ResolvedProvider, String> {
    let mut warnings = Vec::new();
    let (id, safe_overlay) = select_provider_id(project, &mut warnings)?;
    validate_provider_id(&id)?;

    let (mut provider, layer, source_path) =
        load_provider_file(&id, project_root, trusted, &mut warnings)?;

    if let Some(mut overlay) = safe_overlay {
        reject_unsafe_map_keys(project, &mut warnings);
        sanitize_overlay_ensure(&mut overlay, trusted, &mut warnings);
        provider.apply_safe_overlay(overlay);
    }

    // Keep identity aligned with catalog id.
    if provider.name.trim().is_empty() {
        provider.name = id.clone();
    }

    Ok(ResolvedProvider {
        provider,
        id,
        layer,
        source_path,
        warnings,
    })
}

/// Convenience for call sites that ignore layer metadata.
pub fn resolve_provider(
    project: Option<&OffsendProjectConfig>,
    project_root: Option<&Path>,
    trusted: bool,
) -> Result<SandboxProvider, String> {
    Ok(resolve(project, project_root, trusted)?.provider)
}

fn sanitize_overlay_ensure(overlay: &mut SafeOverlay, trusted: bool, warnings: &mut Vec<String>) {
    if trusted {
        return;
    }
    if overlay.ensure == Some(EnsureMode::None) {
        warnings.push(
            "sandbox.provider.ensure: none in .offsend.yml ignored until `offsend policy trust` \
             (using check)"
                .into(),
        );
        overlay.ensure = Some(EnsureMode::Check);
    }
    if let Some(packs) = overlay.packs.as_mut() {
        for (name, pack) in packs.iter_mut() {
            if pack.ensure == Some(EnsureMode::None) {
                warnings.push(format!(
                    "sandbox.provider.packs.{name}.ensure: none ignored until `offsend policy trust` \
                     (using check)"
                ));
                pack.ensure = Some(EnsureMode::Check);
            }
        }
    }
}

fn select_provider_id(
    project: Option<&OffsendProjectConfig>,
    warnings: &mut Vec<String>,
) -> Result<(String, Option<SafeOverlay>), String> {
    let Some(sandbox) = project.and_then(|c| c.sandbox.as_ref()) else {
        return Ok((default_provider_id()?, None));
    };
    let Some(value) = sandbox.get("provider") else {
        return Ok((default_provider_id()?, None));
    };
    match value {
        serde_yaml::Value::String(s) => {
            let id = s.trim().to_string();
            if id.is_empty() {
                return Err("sandbox.provider must not be empty".into());
            }
            Ok((id, None))
        }
        serde_yaml::Value::Mapping(_) => {
            warnings.push(
                "sandbox.provider map form is deprecated for exec fields; use \
                 `provider: <name>` and sandbox.<name>.yml. Only ensure/packs/install_hint \
                 overlays are applied."
                    .into(),
            );
            let overlay: SafeOverlay =
                serde_yaml::from_value(value.clone()).map_err(|e| e.to_string())?;
            // Optional name inside legacy map.
            let id = value
                .get("name")
                .and_then(|v| v.as_str())
                .map(|s| s.trim().to_string())
                .filter(|s| !s.is_empty())
                .unwrap_or(default_provider_id()?);
            Ok((id, Some(overlay)))
        }
        _ => Err("sandbox.provider must be a string name (e.g. nono) or a safe overlay map".into()),
    }
}

fn reject_unsafe_map_keys(project: Option<&OffsendProjectConfig>, warnings: &mut Vec<String>) {
    let Some(value) = project
        .and_then(|c| c.sandbox.as_ref())
        .and_then(|s| s.get("provider"))
    else {
        return;
    };
    let Some(map) = value.as_mapping() else {
        return;
    };
    for key in ["binary", "run_args", "pack_install", "profile_directory", "detect_env"] {
        let key_v = serde_yaml::Value::String(key.into());
        if map.contains_key(&key_v) {
            warnings.push(format!(
                "sandbox.provider.{key} in .offsend.yml is ignored for security; \
                 put exec fields in sandbox.<name>.yml (global or shipped)"
            ));
        }
    }
}

pub fn default_provider_id() -> Result<String, String> {
    if let Ok(text) = fs::read_to_string(global_catalog_path()) {
        if let Ok(cat) = serde_yaml::from_str::<CatalogFile>(&text) {
            let id = cat.default_provider.trim().to_string();
            if !id.is_empty() {
                return Ok(id);
            }
        }
    }
    let cat: CatalogFile =
        serde_yaml::from_str(SHIPPED_CATALOG).map_err(|e| format!("shipped sandbox.yml: {e}"))?;
    let id = cat.default_provider.trim().to_string();
    if id.is_empty() {
        return Err("shipped sandbox.yml: default_provider is empty".into());
    }
    Ok(id)
}

fn validate_provider_id(id: &str) -> Result<(), String> {
    if id.is_empty()
        || id.len() > 64
        || !id
            .chars()
            .all(|c| c.is_ascii_alphanumeric() || c == '-' || c == '_')
    {
        return Err(format!(
            "invalid sandbox.provider `{id}`: use letters, digits, `-` or `_`"
        ));
    }
    Ok(())
}

fn is_shipped_provider_id(id: &str) -> bool {
    shipped_provider_yaml(id).is_some()
}

fn load_provider_file(
    id: &str,
    project_root: Option<&Path>,
    trusted: bool,
    warnings: &mut Vec<String>,
) -> Result<(SandboxProvider, ProviderLayer, Option<PathBuf>), String> {
    if let Some(root) = project_root {
        let path = project_provider_path(root, id);
        if path.is_file() {
            if is_shipped_provider_id(id) {
                warnings.push(format!(
                    "ignoring project {} for shipped provider `{id}` — exec contract \
                     cannot be overridden from the repository (using global/shipped)",
                    path.display()
                ));
            } else if !trusted {
                return Err(format!(
                    "project sandbox provider `{}` requires a trusted policy before use \
                     (exec fields are repo-writable). Review the file, then run: \
                     offsend policy trust",
                    path.display()
                ));
            } else {
                let provider = read_provider_file(&path)?;
                warnings.push(format!(
                    "sandbox provider `{id}` loaded from trusted project path {}",
                    path.display()
                ));
                return Ok((provider, ProviderLayer::Project, Some(path)));
            }
        }
    }
    let global = global_provider_path(id);
    if global.is_file() {
        let provider = read_provider_file(&global)?;
        return Ok((provider, ProviderLayer::Global, Some(global)));
    }
    if let Some(yaml) = shipped_provider_yaml(id) {
        let provider = parse_provider_yaml(yaml)?;
        return Ok((provider, ProviderLayer::Shipped, None));
    }
    Err(format!(
        "sandbox provider `{id}` not found. Expected one of:\n\
         - {}\n\
         - {}\n\
         - shipped sandbox.{id}.yml\n\
         Known shipped providers: {}",
        project_root
            .map(|r| project_provider_path(r, id).display().to_string())
            .unwrap_or_else(|| ".offsend/sandbox.<name>.yml".into()),
        global.display(),
        shipped_provider_names().join(", ")
    ))
}

fn shipped_provider_yaml(id: &str) -> Option<&'static str> {
    match id {
        "nono" => Some(SHIPPED_NONO),
        _ => None,
    }
}

fn shipped_provider_names() -> Vec<&'static str> {
    vec!["nono"]
}

fn read_provider_file(path: &Path) -> Result<SandboxProvider, String> {
    let text = fs::read_to_string(path).map_err(|e| format!("{}: {e}", path.display()))?;
    parse_provider_yaml(&text).map_err(|e| format!("{}: {e}", path.display()))
}

fn parse_provider_yaml(text: &str) -> Result<SandboxProvider, String> {
    serde_yaml::from_str(text).map_err(|e| e.to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn shipped_nono_resolves_by_default() {
        let resolved = resolve(None, None, false).unwrap();
        assert_eq!(resolved.id, "nono");
        assert_eq!(resolved.layer, ProviderLayer::Shipped);
        assert_eq!(resolved.provider.binary, "nono");
        assert_eq!(resolved.provider.ensure, EnsureMode::Check);
        assert!(resolved.provider.pack_install.is_some());
    }

    #[test]
    fn provider_string_selects_name() {
        let yaml = r#"
version: 1
sandbox:
  enabled: true
  provider: nono
"#;
        let cfg = OffsendProjectConfig::parse_yaml(yaml).unwrap();
        let resolved = resolve(Some(&cfg), None, false).unwrap();
        assert_eq!(resolved.id, "nono");
    }

    #[test]
    fn unknown_provider_fails() {
        let yaml = r#"
version: 1
sandbox:
  provider: does-not-exist
"#;
        let cfg = OffsendProjectConfig::parse_yaml(yaml).unwrap();
        let err = resolve(Some(&cfg), None, false).unwrap_err();
        assert!(err.contains("not found"), "{err}");
    }

    #[test]
    fn legacy_map_ignores_binary() {
        let yaml = r#"
version: 1
sandbox:
  provider:
    binary: /opt/evil
    ensure: pull
    packs:
      claude:
        preferred: my-org/claude
        accepted: [my-org/claude]
        base_profile: claude-code
"#;
        let cfg = OffsendProjectConfig::parse_yaml(yaml).unwrap();
        let resolved = resolve(Some(&cfg), None, false).unwrap();
        assert_eq!(resolved.provider.binary, "nono");
        assert_eq!(resolved.provider.ensure, EnsureMode::Pull);
        assert_eq!(
            resolved.provider.pack_for("claude").unwrap().preferred,
            "my-org/claude"
        );
        assert!(resolved
            .warnings
            .iter()
            .any(|w| w.contains("binary") && w.contains("ignored")));
    }

    #[test]
    fn untrusted_ensure_none_forced_to_check() {
        let yaml = r#"
version: 1
sandbox:
  provider:
    ensure: none
"#;
        let cfg = OffsendProjectConfig::parse_yaml(yaml).unwrap();
        let resolved = resolve(Some(&cfg), None, false).unwrap();
        assert_eq!(resolved.provider.ensure, EnsureMode::Check);
        assert!(resolved.warnings.iter().any(|w| w.contains("ensure: none")));
    }

    #[test]
    fn pack_install_argv() {
        let p = resolve(None, None, false).unwrap().provider;
        let (bin, args) = p.pack_install_command("claude").unwrap();
        assert_eq!(bin, PathBuf::from("nono"));
        assert_eq!(args, vec!["pull", "nolabs-ai/claude"]);
    }

    #[test]
    fn expand_run_args_substitutes_placeholders() {
        let p = resolve(None, None, false).unwrap().provider;
        let args = p.expand_run_args(".offsend/nono/offsend-claude.json", "claude");
        assert_eq!(
            args,
            vec![
                "run",
                "--profile",
                "./.offsend/nono/offsend-claude.json",
                "--allow-cwd",
                "--",
                "claude",
            ]
        );
    }

    #[test]
    fn shipped_name_ignores_project_drop_in() {
        let root = std::env::temp_dir().join(format!(
            "offsend-prov-shipped-{}",
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        fs::create_dir_all(root.join(".offsend")).unwrap();
        fs::write(
            root.join(".offsend/sandbox.nono.yml"),
            r#"
name: nono
binary: /bin/echo
profile_directory: .offsend/pwn
run_args: ["PWNED"]
install_hint: "n/a"
ensure: none
"#,
        )
        .unwrap();
        let yaml = r#"
version: 1
sandbox:
  provider: nono
"#;
        let cfg = OffsendProjectConfig::parse_yaml(yaml).unwrap();
        let resolved = resolve(Some(&cfg), Some(&root), true).unwrap();
        assert_eq!(resolved.layer, ProviderLayer::Shipped);
        assert_eq!(resolved.provider.binary, "nono");
        assert!(resolved.warnings.iter().any(|w| w.contains("ignoring project")));
        let _ = fs::remove_dir_all(&root);
    }

    #[test]
    fn custom_project_drop_in_requires_trust() {
        let root = std::env::temp_dir().join(format!(
            "offsend-prov-custom-{}",
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        fs::create_dir_all(root.join(".offsend")).unwrap();
        fs::write(
            root.join(".offsend/sandbox.custom.yml"),
            r#"
name: custom
binary: /usr/bin/true
profile_directory: .offsend/custom
run_args: ["--", "{agent}"]
install_hint: "n/a"
ensure: none
"#,
        )
        .unwrap();
        let yaml = r#"
version: 1
sandbox:
  provider: custom
"#;
        let cfg = OffsendProjectConfig::parse_yaml(yaml).unwrap();
        let err = resolve(Some(&cfg), Some(&root), false).unwrap_err();
        assert!(err.contains("requires a trusted policy"), "{err}");
        let resolved = resolve(Some(&cfg), Some(&root), true).unwrap();
        assert_eq!(resolved.layer, ProviderLayer::Project);
        assert_eq!(resolved.provider.binary, "/usr/bin/true");
        let _ = fs::remove_dir_all(&root);
    }

    #[test]
    fn invalid_provider_ids_rejected() {
        let long = "a".repeat(65);
        let ids = vec![
            "../evil",
            "foo/bar",
            "has space",
            "dot.name",
            "",
            long.as_str(),
        ];
        for id in ids {
            let yaml = format!("version: 1\nsandbox:\n  provider: \"{id}\"\n");
            let cfg = OffsendProjectConfig::parse_yaml(&yaml).unwrap();
            let err = resolve(Some(&cfg), None, false).unwrap_err();
            assert!(
                err.contains("invalid") || err.contains("empty") || err.contains("must not"),
                "id={id:?} err={err}"
            );
        }
    }

    #[test]
    fn provider_type_must_be_string_or_map() {
        let yaml = r#"
version: 1
sandbox:
  provider: 42
"#;
        let cfg = OffsendProjectConfig::parse_yaml(yaml).unwrap();
        let err = resolve(Some(&cfg), None, false).unwrap_err();
        assert!(err.contains("must be a string"), "{err}");
    }

    #[test]
    fn untrusted_per_pack_ensure_none_forced_to_check() {
        let yaml = r#"
version: 1
sandbox:
  provider:
    packs:
      claude:
        preferred: nolabs-ai/claude
        accepted: [nolabs-ai/claude]
        base_profile: claude-code
        ensure: none
"#;
        let cfg = OffsendProjectConfig::parse_yaml(yaml).unwrap();
        let resolved = resolve(Some(&cfg), None, false).unwrap();
        assert_eq!(
            resolved.provider.pack_for("claude").unwrap().ensure,
            Some(EnsureMode::Check)
        );
    }

    #[test]
    fn trusted_ensure_none_allowed() {
        let yaml = r#"
version: 1
sandbox:
  provider:
    ensure: none
"#;
        let cfg = OffsendProjectConfig::parse_yaml(yaml).unwrap();
        let resolved = resolve(Some(&cfg), None, true).unwrap();
        assert_eq!(resolved.provider.ensure, EnsureMode::None);
    }

    #[test]
    fn pack_ensure_overrides_provider_ensure() {
        let mut p = resolve(None, None, false).unwrap().provider;
        p.ensure = EnsureMode::Check;
        p.packs.get_mut("claude").unwrap().ensure = Some(EnsureMode::Pull);
        assert_eq!(p.effective_ensure("claude"), EnsureMode::Pull);
        assert_eq!(p.effective_ensure("codex"), EnsureMode::Check);
    }

    #[test]
    fn pack_install_requires_args_and_pack() {
        let mut p = resolve(None, None, false).unwrap().provider;
        p.pack_install = Some(PackInstall { args: vec![] });
        assert!(p.pack_install_command("claude").unwrap_err().contains("empty"));
        p.pack_install = None;
        assert!(p
            .pack_install_command("claude")
            .unwrap_err()
            .contains("cannot install packs"));
        p.packs.clear();
        p.pack_install = Some(PackInstall {
            args: vec!["pull".into(), "{pack}".into()],
        });
        assert!(p
            .pack_install_command("claude")
            .unwrap_err()
            .contains("no pack"));
    }

    #[test]
    fn legacy_map_ignores_run_args_and_pack_install() {
        let yaml = r#"
version: 1
sandbox:
  provider:
    run_args: ["evil"]
    pack_install:
      args: ["rm", "-rf", "/"]
    detect_env: EVIL
    profile_directory: /tmp/pwn
"#;
        let cfg = OffsendProjectConfig::parse_yaml(yaml).unwrap();
        let resolved = resolve(Some(&cfg), None, false).unwrap();
        assert_ne!(resolved.provider.run_args, vec!["evil"]);
        assert!(resolved.provider.run_args.iter().any(|a| a.contains("{profile}")));
        assert_eq!(resolved.provider.profile_directory, ".offsend/nono");
        assert!(resolved.warnings.iter().any(|w| w.contains("run_args")));
        assert!(resolved.warnings.iter().any(|w| w.contains("pack_install")));
    }

    #[test]
    fn case_sensitive_provider_id_does_not_match_shipped() {
        let yaml = r#"
version: 1
sandbox:
  provider: Nono
"#;
        let cfg = OffsendProjectConfig::parse_yaml(yaml).unwrap();
        let err = resolve(Some(&cfg), None, false).unwrap_err();
        assert!(err.contains("not found"), "{err}");
    }
}
