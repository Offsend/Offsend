//! C ABI for Offsend detection and privacy audit/fix (macOS app bridge).

use offsend_detect::{
    assess_risk, mask_text, restore_text, CustomDictionaryItem, CustomDictionaryKind,
    DetectionEngine, DetectionOptions, DetectionRequest, EntityType, MaskSpan, SensitivityTier,
};
use offsend_policy::{
    build_check_report, check_report_to_json, resolve_audit_configuration, AuditConfigOverrides,
    AuditStatus, FixSelection, PrivacyAuditor, PrivacyFixer, RuleSeverity,
};
use offsend_seal::{SealEngine, SealSpan};
use serde::Deserialize;
use serde_json::{json, Map, Value};
use std::collections::HashSet;
use std::ffi::{CStr, CString};
use std::os::raw::{c_char, c_uchar};
use std::path::Path;
use std::ptr;
use std::slice;

/// Run an FFI body, converting any panic into an error return instead of letting
/// it unwind across the C ABI boundary (which aborts the whole host process).
macro_rules! ffi_guard {
    ($err:expr, $body:block) => {
        match std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| unsafe { $body })) {
            Ok(ret) => ret,
            Err(_) => unsafe {
                fail($err, "offsend: internal error (panic caught at FFI boundary)")
            },
        }
    };
}

/// Scan `text` for sensitive entities. Returns heap-allocated UTF-8 JSON, or NULL on error.
///
/// `options_json_or_null` is optional JSON (camelCase) with `enabledTypes`, `maximumLength`,
/// `honorInlineIgnore`, and `customDictionaries`. Null uses defaults.
///
/// On error, if `err_out` is non-null, writes a heap-allocated error message there
/// (also freed with [`offsend_string_free`]).
#[no_mangle]
pub unsafe extern "C" fn offsend_detect_scan(
    text: *const c_char,
    options_json_or_null: *const c_char,
    err_out: *mut *mut c_char,
) -> *mut c_char {
    ffi_guard!(err_out, {
    clear_err(err_out);
    let Some(text) = read_cstr(text) else {
        return fail(err_out, "text must be a non-null UTF-8 C string");
    };

    let options = if options_json_or_null.is_null() {
        DetectionOptions::default()
    } else {
        let Some(raw) = read_cstr(options_json_or_null) else {
            return fail(err_out, "options_json must be UTF-8 when non-null");
        };
        match parse_detect_options(&raw) {
            Ok(opts) => opts,
            Err(msg) => return fail(err_out, &msg),
        }
    };

    let result = DetectionEngine::scan(&DetectionRequest { text, options });
    let entities: Vec<Value> = result
        .entities
        .iter()
        .map(|e| {
            json!({
                "type": e.entity_type.swift_name(),
                "start": e.start,
                "end": e.end,
                "value": e.value,
                "confidence": e.confidence,
                "source": e.source.swift_name(),
            })
        })
        .collect();

    let payload = json!({
        "scannedText": result.scanned_text,
        "wasTruncated": result.was_truncated,
        "scannedCharacterCount": result.scanned_character_count,
        "entities": entities,
    });

    to_cstring_json(&payload, err_out)
    })
}

/// Run a full privacy audit on `directory_path`. Returns heap-allocated UTF-8 JSON, or NULL.
///
/// `options_json_or_null` is optional JSON with `disabledRuleIDs`,
/// `additionalSkippedDirectoryNames`, `customIgnoreTemplate`, `loadProjectConfig`.
#[no_mangle]
pub unsafe extern "C" fn offsend_privacy_audit(
    directory_path: *const c_char,
    options_json_or_null: *const c_char,
    err_out: *mut *mut c_char,
) -> *mut c_char {
    ffi_guard!(err_out, {
    clear_err(err_out);
    let Some(path) = read_cstr(directory_path) else {
        return fail(err_out, "directory_path must be a non-null UTF-8 C string");
    };

    let overrides = match read_audit_overrides(options_json_or_null) {
        Ok(o) => o,
        Err(msg) => return fail(err_out, &msg),
    };
    let configuration = resolve_audit_configuration(Path::new(&path), &overrides);
    let result = PrivacyAuditor::audit_with(Path::new(&path), &configuration);
    to_cstring_json(&audit_to_json(&result), err_out)
    })
}

/// Audit then apply privacy fixes. `selection_json_or_null` is optional JSON
/// `{"ruleIDs":[...],"patternIDs":[...]}`; null means fix all defaults.
///
/// `options_json_or_null` matches [`offsend_privacy_audit`].
#[no_mangle]
pub unsafe extern "C" fn offsend_privacy_fix(
    directory_path: *const c_char,
    selection_json_or_null: *const c_char,
    options_json_or_null: *const c_char,
    err_out: *mut *mut c_char,
) -> *mut c_char {
    ffi_guard!(err_out, {
    clear_err(err_out);
    let Some(path) = read_cstr(directory_path) else {
        return fail(err_out, "directory_path must be a non-null UTF-8 C string");
    };

    let selection = if selection_json_or_null.is_null() {
        None
    } else {
        let Some(raw) = read_cstr(selection_json_or_null) else {
            return fail(err_out, "selection_json must be UTF-8 when non-null");
        };
        match parse_selection(&raw) {
            Ok(sel) => Some(sel),
            Err(msg) => return fail(err_out, &msg),
        }
    };

    let overrides = match read_audit_overrides(options_json_or_null) {
        Ok(o) => o,
        Err(msg) => return fail(err_out, &msg),
    };
    let configuration = resolve_audit_configuration(Path::new(&path), &overrides);
    let audit = PrivacyAuditor::audit_with(Path::new(&path), &configuration);
    let fix = PrivacyFixer::fix(&audit, &configuration, selection.as_ref());

    let errors: Vec<Value> = fix
        .errors
        .iter()
        .map(|e| json!({ "id": e.id, "message": e.message }))
        .collect();

    let payload = json!({
        "createdRelativePaths": fix.created_relative_paths,
        "updatedRelativePaths": fix.updated_relative_paths,
        "errors": errors,
    });

    to_cstring_json(&payload, err_out)
    })
}

/// Build a Check / Scan API anonymized report (schema v1 + optional fixFiles).
///
/// `tool_version_or_null` may be null (defaults to `"0.0.0"`).
#[no_mangle]
pub unsafe extern "C" fn offsend_check_report(
    directory_path: *const c_char,
    tool_version_or_null: *const c_char,
    err_out: *mut *mut c_char,
) -> *mut c_char {
    ffi_guard!(err_out, {
    clear_err(err_out);
    let Some(path) = read_cstr(directory_path) else {
        return fail(err_out, "directory_path must be a non-null UTF-8 C string");
    };
    let tool_version = if tool_version_or_null.is_null() {
        "0.0.0".to_string()
    } else {
        match read_cstr(tool_version_or_null) {
            Some(v) => v,
            None => return fail(err_out, "tool_version must be UTF-8 when non-null"),
        }
    };

    let report = build_check_report(Path::new(&path), &tool_version);
    match check_report_to_json(&report) {
        Ok(json) => match CString::new(json) {
            Ok(c) => c.into_raw(),
            Err(_) => fail(err_out, "JSON contained interior NUL"),
        },
        Err(e) => fail(err_out, &e),
    }
    })
}

/// Seal entity spans in `text`. `key` must be 32 bytes. `spans_json` is
/// `[{"start":0,"end":5,"value":"...","typeLabel":"EMAIL"}, ...]`.
#[no_mangle]
pub unsafe extern "C" fn offsend_seal_spans(
    key: *const c_uchar,
    key_len: usize,
    text: *const c_char,
    spans_json: *const c_char,
    max_plaintext_bytes: usize,
    err_out: *mut *mut c_char,
) -> *mut c_char {
    ffi_guard!(err_out, {
    clear_err(err_out);
    let Some(key_bytes) = read_key(key, key_len) else {
        return fail(err_out, "key must be a non-null 32-byte buffer");
    };
    let Some(text) = read_cstr(text) else {
        return fail(err_out, "text must be a non-null UTF-8 C string");
    };
    let Some(spans_raw) = read_cstr(spans_json) else {
        return fail(err_out, "spans_json must be a non-null UTF-8 C string");
    };
    let spans = match parse_seal_spans(&spans_raw) {
        Ok(s) => s,
        Err(msg) => return fail(err_out, &msg),
    };
    let max = if max_plaintext_bytes == 0 {
        SealEngine::DEFAULT_MAX_PLAINTEXT_BYTES
    } else {
        max_plaintext_bytes
    };
    let engine = match SealEngine::with_max_plaintext_bytes(key_bytes, max) {
        Ok(e) => e,
        Err(e) => return fail(err_out, &e.to_string()),
    };
    match engine.seal_spans(&text, &spans) {
        Ok(result) => to_cstring_json(
            &json!({
                "sealedText": result.sealed_text,
                "sealedCount": result.sealed_count,
            }),
            err_out,
        ),
        Err(e) => fail(err_out, &e.to_string()),
    }
    })
}

/// Unseal all seal tokens in `text`.
#[no_mangle]
pub unsafe extern "C" fn offsend_unseal_text(
    key: *const c_uchar,
    key_len: usize,
    text: *const c_char,
    err_out: *mut *mut c_char,
) -> *mut c_char {
    ffi_guard!(err_out, {
    clear_err(err_out);
    let Some(key_bytes) = read_key(key, key_len) else {
        return fail(err_out, "key must be a non-null 32-byte buffer");
    };
    let Some(text) = read_cstr(text) else {
        return fail(err_out, "text must be a non-null UTF-8 C string");
    };
    let engine = match SealEngine::new(key_bytes) {
        Ok(e) => e,
        Err(e) => return fail(err_out, &e.to_string()),
    };
    match engine.unseal(&text) {
        Ok(plain) => match CString::new(plain) {
            Ok(c) => c.into_raw(),
            Err(_) => fail(err_out, "unsealed text contained interior NUL"),
        },
        Err(e) => fail(err_out, &e.to_string()),
    }
    })
}

/// Placeholder-mask entity spans. Returns `{maskedText, mapping}`.
#[no_mangle]
pub unsafe extern "C" fn offsend_mask_text(
    text: *const c_char,
    entities_json: *const c_char,
    err_out: *mut *mut c_char,
) -> *mut c_char {
    ffi_guard!(err_out, {
    clear_err(err_out);
    let Some(text) = read_cstr(text) else {
        return fail(err_out, "text must be a non-null UTF-8 C string");
    };
    let Some(raw) = read_cstr(entities_json) else {
        return fail(err_out, "entities_json must be a non-null UTF-8 C string");
    };
    let spans = match parse_mask_spans(&raw) {
        Ok(s) => s,
        Err(msg) => return fail(err_out, &msg),
    };
    let result = mask_text(&text, &spans);
    let mapping: Map<String, Value> = result
        .mapping
        .into_iter()
        .map(|(k, v)| (k, Value::String(v)))
        .collect();
    to_cstring_json(
        &json!({
            "maskedText": result.masked_text,
            "mapping": mapping,
        }),
        err_out,
    )
    })
}

/// Restore placeholders using `mapping_json` object `{placeholder: original}`.
#[no_mangle]
pub unsafe extern "C" fn offsend_restore_text(
    text: *const c_char,
    mapping_json: *const c_char,
    err_out: *mut *mut c_char,
) -> *mut c_char {
    ffi_guard!(err_out, {
    clear_err(err_out);
    let Some(text) = read_cstr(text) else {
        return fail(err_out, "text must be a non-null UTF-8 C string");
    };
    let Some(raw) = read_cstr(mapping_json) else {
        return fail(err_out, "mapping_json must be a non-null UTF-8 C string");
    };
    let mapping: std::collections::HashMap<String, String> = match serde_json::from_str(&raw) {
        Ok(m) => m,
        Err(e) => return fail(err_out, &format!("invalid mapping JSON: {e}")),
    };
    let restored = restore_text(&text, &mapping);
    match CString::new(restored) {
        Ok(c) => c.into_raw(),
        Err(_) => fail(err_out, "restored text contained interior NUL"),
    }
    })
}

/// Assess risk for entity type names. `context_or_null` is `neutral` / `secretsConfig` / `docsOrTests`.
#[no_mangle]
pub unsafe extern "C" fn offsend_risk_assess(
    entity_types_json: *const c_char,
    context_or_null: *const c_char,
    err_out: *mut *mut c_char,
) -> *mut c_char {
    ffi_guard!(err_out, {
    clear_err(err_out);
    let Some(raw) = read_cstr(entity_types_json) else {
        return fail(err_out, "entity_types_json must be a non-null UTF-8 C string");
    };
    let names: Vec<String> = match serde_json::from_str(&raw) {
        Ok(v) => v,
        Err(e) => return fail(err_out, &format!("invalid entity types JSON: {e}")),
    };
    let mut types = Vec::with_capacity(names.len());
    for name in names {
        let Some(t) = EntityType::from_swift_name(&name) else {
            return fail(err_out, &format!("unknown entity type '{name}'"));
        };
        types.push(t);
    }
    let tier = if context_or_null.is_null() {
        SensitivityTier::Neutral
    } else {
        let Some(ctx) = read_cstr(context_or_null) else {
            return fail(err_out, "context must be UTF-8 when non-null");
        };
        match SensitivityTier::from_swift_name(&ctx) {
            Some(t) => t,
            None => return fail(err_out, &format!("unknown sensitivity context '{ctx}'")),
        }
    };
    let assessment = assess_risk(&types, tier);
    to_cstring_json(
        &json!({
            "score": assessment.score,
            "level": assessment.level.swift_name(),
            "recommendedAction": assessment.recommended_action.swift_name(),
            "hasCriticalSecret": assessment.has_critical_secret,
        }),
        err_out,
    )
    })
}

/// Free a string previously returned by this crate (including error messages).
#[no_mangle]
pub unsafe extern "C" fn offsend_string_free(ptr: *mut c_char) {
    if ptr.is_null() {
        return;
    }
    drop(CString::from_raw(ptr));
}

fn audit_to_json(result: &offsend_policy::AuditResult) -> Value {
    let status = match result.status {
        AuditStatus::Pass => "pass",
        AuditStatus::Warning => "warning",
        AuditStatus::Fail => "fail",
    };

    let rule_findings: Vec<Value> = result
        .rule_findings
        .iter()
        .map(|f| {
            json!({
                "id": f.rule.id,
                "toolName": f.rule.tool_name,
                "title": f.rule.title,
                "severity": severity_str(f.rule.severity),
                "satisfied": f.is_satisfied(),
                "matchedPaths": f.matched_relative_paths,
                "exposedPaths": f.exposed_relative_paths,
            })
        })
        .collect();

    let sensitive_pattern_findings: Vec<Value> = result
        .sensitive_pattern_findings
        .iter()
        .map(|f| {
            json!({
                "id": f.pattern.id,
                "title": f.pattern.title,
                "severity": severity_str(f.pattern.severity),
                "exposedPaths": f.exposed_relative_paths,
                "canonicalLine": f.pattern.canonical_ignore_line(),
            })
        })
        .collect();

    let errors: Vec<Value> = result
        .errors
        .iter()
        .map(|e| json!({ "id": e.id, "message": e.message }))
        .collect();

    let missing_sensitive_patterns: Vec<&str> = result
        .missing_sensitive_patterns()
        .iter()
        .map(|f| f.pattern.id.as_str())
        .collect();

    let missing_required_rules: Vec<&str> = result
        .missing_required_rules()
        .iter()
        .map(|f| f.rule.id.as_str())
        .collect();

    let directory = result.directory.to_string_lossy().into_owned();

    json!({
        "directory": directory,
        "status": status,
        "ruleFindings": rule_findings,
        "sensitivePatternFindings": sensitive_pattern_findings,
        "errors": errors,
        "missingSensitivePatterns": missing_sensitive_patterns,
        "missingRequiredRules": missing_required_rules,
    })
}

fn severity_str(severity: RuleSeverity) -> &'static str {
    match severity {
        RuleSeverity::Required => "required",
        RuleSeverity::Recommended => "recommended",
        RuleSeverity::Informational => "informational",
    }
}

#[derive(Debug, Deserialize)]
struct SelectionJson {
    #[serde(rename = "ruleIDs", default)]
    rule_ids: Vec<String>,
    #[serde(rename = "patternIDs", default)]
    pattern_ids: Vec<String>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct DetectOptionsJson {
    #[serde(default)]
    enabled_types: Option<Vec<String>>,
    #[serde(default)]
    maximum_length: Option<usize>,
    #[serde(default)]
    honor_inline_ignore: Option<bool>,
    #[serde(default)]
    custom_dictionaries: Option<Vec<CustomDictionaryJson>>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct CustomDictionaryJson {
    kind: String,
    value: String,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct AuditOptionsJson {
    #[serde(default, rename = "disabledRuleIDs")]
    disabled_rule_ids: Option<Vec<String>>,
    #[serde(default)]
    additional_skipped_directory_names: Option<Vec<String>>,
    #[serde(default)]
    custom_ignore_template: Option<String>,
    #[serde(default)]
    load_project_config: Option<bool>,
}

unsafe fn read_audit_overrides(
    options_json_or_null: *const c_char,
) -> Result<AuditConfigOverrides, String> {
    if options_json_or_null.is_null() {
        return Ok(AuditConfigOverrides::new());
    }
    let Some(raw) = read_cstr(options_json_or_null) else {
        return Err("options_json must be UTF-8 when non-null".into());
    };
    parse_audit_overrides(&raw)
}

fn parse_audit_overrides(raw: &str) -> Result<AuditConfigOverrides, String> {
    let parsed: AuditOptionsJson =
        serde_json::from_str(raw).map_err(|e| format!("invalid audit options JSON: {e}"))?;
    let mut overrides = AuditConfigOverrides::new();
    if let Some(ids) = parsed.disabled_rule_ids {
        overrides.disabled_rule_ids = ids.into_iter().collect();
    }
    if let Some(names) = parsed.additional_skipped_directory_names {
        overrides.additional_skipped_directory_names = names.into_iter().collect();
    }
    if let Some(template) = parsed.custom_ignore_template {
        let trimmed = template.trim().to_string();
        if !trimmed.is_empty() {
            overrides.custom_ignore_template = Some(trimmed);
        }
    }
    if let Some(load) = parsed.load_project_config {
        overrides.load_project_config = load;
    }
    Ok(overrides)
}

fn parse_detect_options(raw: &str) -> Result<DetectionOptions, String> {
    let parsed: DetectOptionsJson =
        serde_json::from_str(raw).map_err(|e| format!("invalid detect options JSON: {e}"))?;
    let mut options = DetectionOptions::default();
    if let Some(types) = parsed.enabled_types {
        let mut set = HashSet::new();
        for name in types {
            let Some(t) = EntityType::from_swift_name(&name) else {
                return Err(format!("unknown entity type '{name}'"));
            };
            set.insert(t);
        }
        options.enabled_types = set;
    }
    if let Some(max) = parsed.maximum_length {
        options.maximum_length = max;
    }
    if let Some(honor) = parsed.honor_inline_ignore {
        options.honor_inline_ignore = honor;
    }
    if let Some(dicts) = parsed.custom_dictionaries {
        let mut items = Vec::with_capacity(dicts.len());
        for d in dicts {
            let Some(kind) = CustomDictionaryKind::from_swift_name(&d.kind) else {
                return Err(format!("unknown custom dictionary kind '{}'", d.kind));
            };
            items.push(CustomDictionaryItem {
                kind,
                value: d.value,
            });
        }
        options.custom_dictionaries = items;
    }
    Ok(options)
}

fn parse_selection(raw: &str) -> Result<FixSelection, String> {
    let parsed: SelectionJson =
        serde_json::from_str(raw).map_err(|e| format!("invalid selection JSON: {e}"))?;
    Ok(FixSelection::new(
        parsed.rule_ids.into_iter().collect::<HashSet<_>>(),
        parsed.pattern_ids.into_iter().collect::<HashSet<_>>(),
    ))
}

unsafe fn read_cstr(ptr: *const c_char) -> Option<String> {
    if ptr.is_null() {
        return None;
    }
    CStr::from_ptr(ptr).to_str().ok().map(|s| s.to_owned())
}

unsafe fn read_key<'a>(key: *const c_uchar, key_len: usize) -> Option<&'a [u8]> {
    if key.is_null() || key_len != 32 {
        return None;
    }
    Some(slice::from_raw_parts(key, key_len))
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct SealSpanJson {
    start: usize,
    end: usize,
    value: String,
    type_label: String,
}

fn parse_seal_spans(raw: &str) -> Result<Vec<SealSpan>, String> {
    let parsed: Vec<SealSpanJson> =
        serde_json::from_str(raw).map_err(|e| format!("invalid seal spans JSON: {e}"))?;
    Ok(parsed
        .into_iter()
        .map(|s| SealSpan {
            start: s.start,
            end: s.end,
            value: s.value,
            type_label: s.type_label,
        })
        .collect())
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct MaskSpanJson {
    start: usize,
    end: usize,
    value: String,
    #[serde(rename = "type")]
    entity_type: String,
}

fn parse_mask_spans(raw: &str) -> Result<Vec<MaskSpan>, String> {
    let parsed: Vec<MaskSpanJson> =
        serde_json::from_str(raw).map_err(|e| format!("invalid mask entities JSON: {e}"))?;
    let mut spans = Vec::with_capacity(parsed.len());
    for s in parsed {
        let Some(entity_type) = EntityType::from_swift_name(&s.entity_type) else {
            return Err(format!("unknown entity type '{}'", s.entity_type));
        };
        spans.push(MaskSpan {
            start: s.start,
            end: s.end,
            value: s.value,
            entity_type,
        });
    }
    Ok(spans)
}

unsafe fn clear_err(err_out: *mut *mut c_char) {
    if !err_out.is_null() {
        *err_out = ptr::null_mut();
    }
}

unsafe fn set_err(err_out: *mut *mut c_char, message: &str) {
    if err_out.is_null() {
        return;
    }
    *err_out = match CString::new(message) {
        Ok(c) => c.into_raw(),
        Err(_) => CString::new("invalid error message")
            .map(|c| c.into_raw())
            .unwrap_or(ptr::null_mut()),
    };
}

unsafe fn fail(err_out: *mut *mut c_char, message: &str) -> *mut c_char {
    set_err(err_out, message);
    ptr::null_mut()
}

unsafe fn to_cstring_json(value: &Value, err_out: *mut *mut c_char) -> *mut c_char {
    match serde_json::to_string(value) {
        Ok(s) => match CString::new(s) {
            Ok(c) => c.into_raw(),
            Err(_) => fail(err_out, "JSON contained interior NUL"),
        },
        Err(e) => fail(err_out, &format!("JSON serialize failed: {e}")),
    }
}
