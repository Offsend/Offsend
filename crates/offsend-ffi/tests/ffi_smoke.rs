use std::ffi::{CStr, CString};
use std::os::raw::c_char;
use std::ptr;

unsafe fn take_cstr(ptr: *mut c_char) -> Option<String> {
    if ptr.is_null() {
        return None;
    }
    let s = CStr::from_ptr(ptr).to_string_lossy().into_owned();
    offsend_ffi::offsend_string_free(ptr);
    Some(s)
}

#[test]
fn detect_scan_returns_json() {
    let text = CString::new("email me at alice@example.com please").unwrap();
    let mut err: *mut c_char = ptr::null_mut();
    unsafe {
        let raw = offsend_ffi::offsend_detect_scan(text.as_ptr(), ptr::null(), &mut err);
        assert!(err.is_null(), "err={:?}", take_cstr(err));
        let json = take_cstr(raw).expect("json");
        assert!(json.contains("scannedText"));
        assert!(json.contains("entities"));
    }
}

unsafe fn scan_with_options(text: &str, options: &str) -> Result<String, String> {
    let text = CString::new(text).unwrap();
    let options = CString::new(options).unwrap();
    let mut err: *mut c_char = ptr::null_mut();
    let raw = offsend_ffi::offsend_detect_scan(text.as_ptr(), options.as_ptr(), &mut err);
    match take_cstr(raw) {
        Some(json) => Ok(json),
        None => Err(take_cstr(err).unwrap_or_default()),
    }
}

#[test]
fn detect_scan_applies_high_entropy_sensitivity() {
    let text = "Zq8Lm3Xv7Rt2Yb9Kp4Wn6Hc1Jd5Fs0";
    unsafe {
        let strict = scan_with_options(text, r#"{"highEntropySensitivity":"strict"}"#).unwrap();
        assert!(strict.contains("highEntropyString"), "strict: {strict}");
        let normal = scan_with_options(text, r#"{"highEntropySensitivity":"normal"}"#).unwrap();
        assert!(!normal.contains("highEntropyString"), "normal: {normal}");
        let default = scan_with_options(text, "{}").unwrap();
        assert!(!default.contains("highEntropyString"), "default: {default}");
    }
}

#[test]
fn detect_scan_rejects_unknown_high_entropy_sensitivity() {
    unsafe {
        let err = scan_with_options("x", r#"{"highEntropySensitivity":"paranoid"}"#).unwrap_err();
        assert!(err.contains("paranoid"), "err={err}");
    }
}

#[test]
fn audit_temp_directory() {
    let dir = tempfile_dir();
    let path = CString::new(dir.to_string_lossy().as_bytes()).unwrap();
    let mut err: *mut c_char = ptr::null_mut();
    unsafe {
        let raw = offsend_ffi::offsend_privacy_audit(path.as_ptr(), ptr::null(), &mut err);
        assert!(err.is_null(), "err={:?}", take_cstr(err));
        let json = take_cstr(raw).expect("json");
        assert!(json.contains("ruleFindings"));
        assert!(json.contains("status"));
    }
    let _ = std::fs::remove_dir_all(&dir);
}

#[test]
fn check_report_temp_directory_with_env() {
    let dir = tempfile_dir();
    std::fs::write(dir.join(".env"), "SECRET=abc\n").unwrap();
    let path = CString::new(dir.to_string_lossy().as_bytes()).unwrap();
    let version = CString::new("ffi-test").unwrap();
    let mut err: *mut c_char = ptr::null_mut();
    unsafe {
        let raw = offsend_ffi::offsend_check_report(path.as_ptr(), version.as_ptr(), &mut err);
        assert!(err.is_null(), "err={:?}", take_cstr(err));
        let json = take_cstr(raw).expect("json");
        assert!(json.contains("schemaVersion"));
        assert!(json.contains("exposedPatterns"));
        assert!(json.contains("ffi-test"));
    }
    let _ = std::fs::remove_dir_all(&dir);
}

fn tempfile_dir() -> std::path::PathBuf {
    let dir = std::env::temp_dir().join(format!(
        "offsend-ffi-test-{}",
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_nanos()
    ));
    std::fs::create_dir_all(&dir).unwrap();
    dir
}
