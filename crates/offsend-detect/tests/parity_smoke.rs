use offsend_detect::{
    CustomDictionaryItem, CustomDictionaryKind, DetectionEngine, DetectionOptions, DetectionRequest,
    DetectionSource, EntityType,
};

#[test]
fn detects_email_and_ipv4() {
    let text = "contact user@example.com from 192.168.0.1 please";
    let result = DetectionEngine::scan(&DetectionRequest::new(text));
    let types: Vec<_> = result.entities.iter().map(|e| e.entity_type).collect();
    assert!(types.contains(&EntityType::Email), "{types:?}");
    assert!(types.contains(&EntityType::IpAddress), "{types:?}");
}

#[test]
fn luhn_rejects_invalid_card_shape() {
    let text = "card 4111 1111 1111 1112";
    let result = DetectionEngine::scan(&DetectionRequest::new(text));
    assert!(
        !result
            .entities
            .iter()
            .any(|e| e.entity_type == EntityType::CreditCardLike),
        "{:?}",
        result.entities
    );
}

#[test]
fn luhn_accepts_valid_test_card() {
    let text = "card 4242 4242 4242 4242";
    let result = DetectionEngine::scan(&DetectionRequest::new(text));
    assert!(
        result
            .entities
            .iter()
            .any(|e| e.entity_type == EntityType::CreditCardLike),
        "{:?}",
        result.entities
    );
}

#[test]
fn iban_mod97() {
    let text = "pay to DE89370400440532013000 now";
    let result = DetectionEngine::scan(&DetectionRequest::new(text));
    assert!(
        result
            .entities
            .iter()
            .any(|e| e.entity_type == EntityType::Iban),
        "{:?}",
        result.entities
    );
}

#[test]
fn money_rejects_swift_closure_arg() {
    let text = "map { $0 + 1 }";
    let result = DetectionEngine::scan(&DetectionRequest::new(text));
    assert!(
        !result
            .entities
            .iter()
            .any(|e| e.entity_type == EntityType::Money),
        "{:?}",
        result.entities
    );
}

#[test]
fn placeholder_angle_brackets_dropped() {
    let text = "token=<your-api-key-here>";
    let result = DetectionEngine::scan(&DetectionRequest::new(text));
    assert!(
        !result.entities.iter().any(|e| e.entity_type.is_secret()),
        "{:?}",
        result.entities
    );
}

#[test]
fn builtin_rules_load_and_compile() {
    let result = DetectionEngine::scan(&DetectionRequest::new("hello world"));
    assert!(result.entities.is_empty());
    assert_eq!(result.scanned_text, "hello world");
}

#[test]
fn custom_dictionary_literal_match() {
    let mut options = DetectionOptions::default();
    options.custom_dictionaries = vec![CustomDictionaryItem {
        kind: CustomDictionaryKind::Client,
        value: "Acme Corp".into(),
    }];
    let result = DetectionEngine::scan(&DetectionRequest {
        text: "Meeting with Acme Corp tomorrow".into(),
        options,
    });
    assert!(
        result.entities.iter().any(|e| {
            e.entity_type == EntityType::CustomClient
                && e.source == DetectionSource::CustomDictionary
                && e.value == "Acme Corp"
        }),
        "{:?}",
        result.entities
    );
}

#[test]
fn honor_inline_ignore_same_line() {
    let mut options = DetectionOptions::default();
    options.honor_inline_ignore = true;
    let result = DetectionEngine::scan(&DetectionRequest {
        text: "contact user@example.com # offsend:ignore\n".into(),
        options,
    });
    assert!(
        !result
            .entities
            .iter()
            .any(|e| e.entity_type == EntityType::Email),
        "{:?}",
        result.entities
    );
}

#[test]
fn honor_inline_ignore_next_line() {
    let mut options = DetectionOptions::default();
    options.honor_inline_ignore = true;
    let result = DetectionEngine::scan(&DetectionRequest {
        text: "# offsend:ignore-next-line\ncontact user@example.com\n".into(),
        options,
    });
    assert!(
        !result
            .entities
            .iter()
            .any(|e| e.entity_type == EntityType::Email),
        "{:?}",
        result.entities
    );
}

#[test]
fn seal_token_suppresses_high_entropy_and_phone() {
    // Golden corpus token: payload previously false-triggered highEntropy → {{SECRET_1}}.
    let text = "{{EMAIL:v1.ay0pF8pgS30I1UA9cZxHpe-EDanFkPg3ybpjGzk-L3jor00}}";
    let result = DetectionEngine::scan(&DetectionRequest::new(text));
    assert!(
        result.entities.is_empty(),
        "seal ciphertext must not surface as findings: {:?}",
        result.entities
    );

    // Digit runs after '-' in base64url also false-trigger phone.
    let phoneish = "{{EMAIL:v1.xx-123-456-7890}}";
    let phone_result = DetectionEngine::scan(&DetectionRequest::new(phoneish));
    assert!(
        !phone_result
            .entities
            .iter()
            .any(|e| e.entity_type == EntityType::Phone),
        "{:?}",
        phone_result.entities
    );
}

#[test]
fn seal_token_suppresses_api_key_generic_on_secret_label() {
    // Seal placeholders use SECRET:v1.<ciphertext>, which matches apiKeyGeneric's
    // `secret\s*[:=]\s*…` pattern — must not fire on real sealed copies.
    let text = "{{SECRET:v1.wUNe0JIRW0_41ZXVPaArASkRmoJXetbI1Or38nABCDEFGH}}";
    let result = DetectionEngine::scan(&DetectionRequest::new(text));
    assert!(
        result.entities.is_empty(),
        "seal framing must not surface as apiKeyGeneric: {:?}",
        result.entities
    );
}

#[test]
fn seal_token_keeps_critical_secret_inside_fake_framing() {
    // Framing alone is not trusted — a live key wrapped in {{TYPE:v1.…}} must still fire.
    // Avoid placeholder substrings like "EXAMPLE" (sanitizer drops those).
    let text = "{{FAKE:v1.AKIAABCDEFGHIJ012345}}";
    let result = DetectionEngine::scan(&DetectionRequest::new(text));
    assert!(
        result
            .entities
            .iter()
            .any(|e| e.entity_type == EntityType::AwsAccessKeyId),
        "{:?}",
        result.entities
    );
}

fn detects_secret(text: &str) -> bool {
    DetectionEngine::scan(&DetectionRequest::new(text))
        .entities
        .iter()
        .any(|e| e.entity_type.counts_as_critical_secret())
}

#[test]
fn detects_added_provider_tokens() {
    let cases = [
        "key AIzaSyD-2gxS3n4pQrStUvWxYz0123456789abc here",
        "anthropic sk-ant-api03-ABCdef123456ghiJKL used",
        "gitlab glpat-ABCdef123456ghiJKL789 token",
        "runner glrt-ABCdef123456ghiJKL789 token",
        "npm npm_0123456789abcdefghijklmnopqrstuvwxyz set",
        "hf hf_ABCdefGHIjklMNOpqrSTUvwxYZ0123456789 token",
        "sg SG.ABCDEFGHIJKLMNOPQRSTUV.0123456789abcdefghijklmnopqrstuvwxyzABCDEFG done",
        "oauth GOCSPX-ABCdef123456ghiJKL789mnopqrs value",
        "hook https://hooks.slack.com/services/T00000000/B11111111/abcdefABCDEF0123456789 posted",
        "db dapi0123456789abcdef0123456789abcdef token",
    ];
    for text in cases {
        assert!(detects_secret(text), "expected secret finding in: {text}");
    }
}

#[test]
fn ignores_benign_lookalikes() {
    // Must not fire on ordinary prose / identifiers.
    assert!(!detects_secret("the npm_config option controls install behaviour"));
    assert!(!detects_secret("visit https://hooks.example.com/services/list for docs"));
}

#[test]
fn scan_including_encoded_surfaces_hidden_secret() {
    // A live AWS key hex-encoded (as `secret | xxd`) must still surface — the
    // `| base64`/hex exfil bypass. Avoid the "EXAMPLE" placeholder substring.
    let secret = "AKIAABCDEFGHIJ012345";
    let hex: String = secret.bytes().map(|b| format!("{b:02x}")).collect();
    let text = format!("command output: {hex} done");

    let scan = DetectionEngine::scan_including_encoded(&text);
    assert!(
        scan.entities
            .iter()
            .any(|e| e.entity_type == EntityType::AwsAccessKeyId),
        "expected AWS key decoded from hex blob: {:?}",
        scan.entities
    );

    // The plain scan must NOT decode — that is exactly the gap being closed.
    let plain = DetectionEngine::scan(&DetectionRequest::new(text));
    assert!(
        !plain
            .entities
            .iter()
            .any(|e| e.entity_type == EntityType::AwsAccessKeyId),
        "plain scan should not decode the blob: {:?}",
        plain.entities
    );
}

fn phone_values(text: &str) -> Vec<String> {
    DetectionEngine::scan(&DetectionRequest::new(text))
        .entities
        .into_iter()
        .filter(|e| e.entity_type == EntityType::Phone)
        .map(|e| e.value)
        .collect()
}

#[test]
fn phone_rejects_common_false_positives() {
    let samples = [
        "issue #1234567 fixed",
        "order 1234567890 shipped",
        "ticket ABC-1234567",
        "short 1234567",
        "bare 4155552671",
        "uuid 550e8400-e29b-41d4-a716-446655440000",
        "coords 37.7749 122.4194",
        "ssn-like 123-45-6789",
        "date 2024-01-15 done",
        "time 12.34.56 clock",
        "zip 90210-1234 area",
        "ip 10.20.30.40 gateway",
        "build 12.34.56",
    ];
    for s in samples {
        let phones = phone_values(s);
        assert!(
            phones.is_empty(),
            "unexpected phone in {s:?}: {phones:?}"
        );
    }
}

#[test]
fn phone_detects_formatted_numbers() {
    let samples = [
        ("call +1 415 555 2671 now", "+1 415 555 2671"),
        ("call (415) 555-2671 now", "(415) 555-2671"),
        ("call 415-555-2671 now", "415-555-2671"),
        ("call 415.555.2671 now", "415.555.2671"),
        ("call +7 999 123-45-67 now", "+7 999 123-45-67"),
        ("call +7 (999) 123-45-67 now", "+7 (999) 123-45-67"),
        ("call +44 20 7946 0958 now", "+44 20 7946 0958"),
        ("call 8 999 123-45-67 now", "8 999 123-45-67"),
        ("call +12025551234 now", "+12025551234"),
    ];
    for (text, expected) in samples {
        let phones = phone_values(text);
        assert!(
            phones.iter().any(|p| p == expected),
            "expected {expected:?} in {text:?}, got {phones:?}"
        );
    }
}

#[test]
fn database_url_seals_password_span_only() {
    let text = "DATABASE_URL=postgres://admin:correct-horse-battery@db.internal/prod";
    let result = DetectionEngine::scan(&DetectionRequest::new(text));
    let found = result
        .entities
        .iter()
        .find(|e| e.entity_type == EntityType::DatabaseUrlWithPassword)
        .expect("database url password");
    assert_eq!(found.value, "correct-horse-battery");
    assert_eq!(
        found.entity_type.placeholder_prefix(),
        "PASSWORD"
    );
    assert!(text.contains("postgres://admin:"));
    assert!(!text[found.start..found.end].contains("postgres"));
    assert!(!text[found.start..found.end].contains("db.internal"));
}

#[test]
fn https_url_with_userinfo_seals_password_only() {
    let text = "proxy=https://deploy:s3cret-pass@git.example.com/org/repo.git";
    let result = DetectionEngine::scan(&DetectionRequest::new(text));
    let found = result
        .entities
        .iter()
        .find(|e| e.entity_type == EntityType::DatabaseUrlWithPassword)
        .expect("https userinfo password");
    assert_eq!(found.value, "s3cret-pass");
}

#[test]
fn bearer_token_seals_token_not_scheme() {
    let token = "abcdefghijklmnopqrstuvwxyz012345";
    let text = format!("Authorization: Bearer {token}");
    let result = DetectionEngine::scan(&DetectionRequest::new(text));
    let found = result
        .entities
        .iter()
        .find(|e| e.entity_type == EntityType::BearerToken)
        .expect("bearer");
    assert_eq!(found.value, token);
    assert_eq!(found.entity_type.placeholder_prefix(), "BEARER_TOKEN");
}

#[test]
fn empty_url_password_is_not_a_partial_span() {
    let text = "DATABASE_URL=postgres://admin:@db.internal/prod";
    let result = DetectionEngine::scan(&DetectionRequest::new(text));
    assert!(
        result
            .entities
            .iter()
            .filter(|e| e.entity_type == EntityType::DatabaseUrlWithPassword)
            .all(|e| !e.value.is_empty()),
        "{:?}",
        result.entities
    );
}

#[test]
fn json_escaped_newline_keeps_url_password_and_aws_key() {
    let plain = "DATABASE_URL=postgres://admin:my-real-looking-pass-781492@db.internal/prod\nAWS_ACCESS_KEY_ID=AKIA1234567890ABCDEF";
    let compact = serde_json::json!({
        "content": [{ "text": plain }]
    })
    .to_string();
    assert!(compact.contains("\\n"), "{compact}");

    for text in [plain.to_string(), compact] {
        let result = DetectionEngine::scan(&DetectionRequest::new(text.clone()));
        let types: Vec<_> = result.entities.iter().map(|e| e.entity_type).collect();
        let password = result
            .entities
            .iter()
            .find(|e| e.entity_type == EntityType::DatabaseUrlWithPassword)
            .unwrap_or_else(|| panic!("password missing in {text:?}: {types:?}"));
        let aws = result
            .entities
            .iter()
            .find(|e| e.entity_type == EntityType::AwsAccessKeyId)
            .unwrap_or_else(|| panic!("aws key missing in {text:?}: {types:?}"));
        assert_eq!(password.value, "my-real-looking-pass-781492");
        assert_eq!(&text[password.start..password.end], password.value);
        assert_eq!(aws.value, "AKIA1234567890ABCDEF");
        assert_eq!(&text[aws.start..aws.end], aws.value);
    }
}

fn critical_secret_values(text: &str) -> Vec<String> {
    DetectionEngine::scan(&DetectionRequest::new(text))
        .entities
        .into_iter()
        .filter(|e| e.entity_type.counts_as_critical_secret())
        .map(|e| e.value)
        .collect()
}

#[test]
fn labeled_password_seals_value_only() {
    let cases = [
        ("password: Zq8$Lm3!Xv7#Rt2", "Zq8$Lm3!Xv7#Rt2"),
        ("DB_PASSWORD=Hunter2Hunter2", "Hunter2Hunter2"),
        (r#"{"password": "s3cr3t-Pa55w0rd"}"#, "s3cr3t-Pa55w0rd"),
        ("pwd='Qw3rty!Pass'", "Qw3rty!Pass"),
        (r#"passphrase = "N0t-Gu3ss4ble""#, "N0t-Gu3ss4ble"),
        ("Password: Abcd1234! for the vpn", "Abcd1234!"),
    ];
    for (text, expected) in cases {
        let values = critical_secret_values(text);
        assert!(
            values.iter().any(|v| v == expected),
            "expected {expected:?} in {text:?}, got {values:?}"
        );
    }
}

#[test]
fn labeled_password_ignores_code_and_env_references() {
    let samples = [
        "password = os.environ['DB_PASSWORD']",
        "password: process.env.DB_PASSWORD",
        "password = getPassword()",
        "password: Optional[str] = None",
        "PASSWORD=$DB_PASSWORD",
        r#"password: "${DB_PASSWORD}""#,
        "PWD=/Users/me/project2",
        r#"password: "<your password>""#,
        "password=********",
        "Password: Must be at least 8 characters",
        "password: string",
    ];
    for s in samples {
        let values = critical_secret_values(s);
        assert!(values.is_empty(), "unexpected secret in {s:?}: {values:?}");
    }
}

fn detects_high_entropy(text: &str) -> bool {
    DetectionEngine::scan(&DetectionRequest::new(text))
        .entities
        .iter()
        .any(|e| e.entity_type == EntityType::HighEntropyString)
}

#[test]
fn high_entropy_keeps_current_coverage() {
    let cases = [
        "3f9c2a7e1b4d6f8091a2b3c4d5e6f7a8b9c0d1e2",
        "9b1e4c7a2d5f8e0b3a6c9d2e5f8a1b4c7d0e3f6a9b2c5d8e1f4a7b0c3d6e9f2a",
        "Zq8Lm3Xv7Rt2Yb9Kp4Wn6Hc1Jd5Fs0GaQe8UiO3+Mx7Vz2NbT6==",
        "SECRET_KEY=Zq8Lm3Xv7Rt2Yb9Kp4Wn6Hc1Jd5Fs0GaQe8UiO3Mx7",
        "8Zq8Lm3Xv7Rt2Yb9Kp4Wn6Hc1Jd5Fs0GaQe8UiO3Mx7Vz2NbT6",
        "Zq8Lm3Xv7Rt2Yb9Kp4Wn6Hc1-Jd5Fs0GaQe8UiO3Mx7Vz2NbT6",
    ];
    for text in cases {
        assert!(detects_high_entropy(text), "expected highEntropyString in: {text}");
    }
}

#[test]
fn high_entropy_ignores_identifiers_and_paths() {
    let samples = [
        "getUserAccountPreferencesFromRemoteConfigurationStore",
        "/usr/local/lib/python3/site-packages/offsend/detect/rules",
    ];
    for s in samples {
        assert!(!detects_high_entropy(s), "unexpected highEntropyString in: {s}");
    }
}

#[test]
fn high_entropy_detects_bare_random_strings_starting_with_letter() {
    let cases = [
        // Issue #57: 50 alphanumeric characters, no key name or prefix.
        "Zq8Lm3Xv7Rt2Yb9Kp4Wn6Hc1Jd5Fs0GaQe8UiO3Mx7Vz2NbT6",
        "af9c2a7e1b4d6f8091a2b3c4d5e6f7a8b9c0d1e2",
        "D026C0BC5F7B183C9417C640B62313724EB9E02858555C4D8BB51640207B9F78",
        "rUQB/Js67u/J9krk+4GH1+7sOv6mlNZBsjE8L67+tpBX",
        "gBv4RuwHQQfgniiJvfKFuSNWxox3+D0ubBNJoBjc4g==",
        "h8F8buP9bs29tBy-L59ERu0oqNI0sUTWrgTMbYPcp_Gc",
        "gj6mww61ftv9xujibmfqbqgd3imdsnc61qtjs16inu1o",
        // base64 with `/` but no `+`/`=` used to be dropped as a path.
        "E1ea9QXv/HJnLyj67yse92s/OBk7Kj5etA1CiPbk5Z9k",
        // Contains an IBAN-shaped run that fails mod97; it used to win overlap
        // and then get dropped, taking this finding with it.
        "2Tpb1OrXURvmGzn+IVgSffoAAY+ty517Ja068tivSNs7",
    ];
    for text in cases {
        assert!(detects_high_entropy(text), "expected highEntropyString in: {text}");
    }
}

#[test]
fn high_entropy_ignores_real_paths() {
    let samples = [
        "/private/var/folders/xy/1n4k8x2s7q9w3v5b6m0c/T/offsend-scan",
        "/Users/hudishkin/Projects/offsend/macos/crates/offsend-detect/src",
        "apps/macos/Core/DetectionCore/Sources/OverlapResolver",
        "/home/runner/work/Offsend/Offsend/target/release/build",
        "/var/lib/docker/overlay2/l/ABCDEF1234567890QWERTY/diff",
        "/api/v1/users/42/orders/2026/11/07/items/export",
        "/dev/disk3s1/System/Volumes/Data/private/tmp/build42",
    ];
    for s in samples {
        assert!(!detects_high_entropy(s), "unexpected highEntropyString in: {s}");
    }
}

#[test]
fn high_entropy_detects_random_string_in_context() {
    let secret = "Zq8Lm3Xv7Rt2Yb9Kp4Wn6Hc1Jd5Fs0GaQe8UiO3Mx7Vz2NbT6";
    let cases = [
        format!("here it is {secret} keep it safe"),
        format!(r#"{{"value": "{secret}"}}"#),
        format!("value='{secret}'"),
        format!("line one\n{secret}\nline three"),
        format!("({secret})"),
    ];
    for text in cases {
        let found = DetectionEngine::scan(&DetectionRequest::new(text.clone()))
            .entities
            .into_iter()
            .find(|e| e.entity_type == EntityType::HighEntropyString)
            .unwrap_or_else(|| panic!("expected highEntropyString in: {text}"));
        // A standalone `(secret)` line may be covered whole by the symbol rule.
        assert!(found.value.contains(secret), "span {:?} in {text:?}", found.value);
    }
}

#[test]
fn high_entropy_ignores_names_slugs_and_repetition() {
    let samples = [
        "my-component-name-v2-build-2026-11-07-release-final",
        "getUserAccount2PreferencesFromRemoteConfigurationStoreV3",
        "test_detects_added_provider_tokens_v2_2026_regression",
        "feature-flag-enable-new-onboarding-flow-2026q4-rollout",
        "com_example_app_release_build_2026_11_07_arm64_universal",
        "user_profile_settings_dark_mode_enabled_v1_default",
        "2026-11-07T10-23-00-report-quarterly-summary-final-v3",
        "DocumentationGenerator2026InternalReleaseCandidateBuild",
        "kubernetes-deployment-offsend-api-production-eu-west-1",
        "aws-lambda-function-offsend-scanner-prod-us-east-1-v12",
        "ProjectOffsendMacOSApplicationVersion035BuildNumber1287",
        "x86_64-apple-darwin-release-build-artifacts-universal2",
        "0000000000000000000000000000000000000000",
        "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA1",
        "abcdefabcdefabcdefabcdefabcdefabcdefabcdef12",
        "src/components/settings/panels/SettingsDetectionPanel2.swift",
    ];
    for s in samples {
        assert!(!detects_high_entropy(s), "unexpected highEntropyString in: {s}");
    }
}

/// Deterministic xorshift so the corpus is identical on every run.
struct XorShift(u64);

impl XorShift {
    fn next(&mut self) -> u64 {
        self.0 ^= self.0 << 13;
        self.0 ^= self.0 >> 7;
        self.0 ^= self.0 << 17;
        self.0
    }

    fn string(&mut self, alphabet: &[u8], len: usize) -> String {
        (0..len)
            .map(|_| alphabet[(self.next() % alphabet.len() as u64) as usize] as char)
            .collect()
    }
}

fn high_entropy_detection_rate(alphabet: &str, len: usize, samples: usize) -> f64 {
    let mut rng = XorShift(0x9E37_79B9_7F4A_7C15);
    let detected = (0..samples)
        .filter(|_| detects_high_entropy(&rng.string(alphabet.as_bytes(), len)))
        .count();
    detected as f64 / samples as f64
}

#[test]
fn high_entropy_detection_rate_on_random_corpus() {
    const LOWER: &str = "abcdefghijklmnopqrstuvwxyz";
    const UPPER: &str = "ABCDEFGHIJKLMNOPQRSTUVWXYZ";
    const DIGITS: &str = "0123456789";
    let base62 = format!("{LOWER}{UPPER}{DIGITS}");
    let base64 = format!("{base62}+/");
    let base64url = format!("{base62}-_");
    let base36 = format!("{LOWER}{DIGITS}");
    let cases: [(&str, &str, usize, f64); 7] = [
        ("hex", "0123456789abcdef", 40, 0.99),
        ("HEX", "0123456789ABCDEF", 64, 0.99),
        ("base62", &base62, 40, 0.99),
        ("base62", &base62, 64, 0.99),
        ("base64", &base64, 44, 0.99),
        ("base64url", &base64url, 43, 0.99),
        ("base36", &base36, 40, 0.90),
    ];
    for (name, alphabet, len, min_rate) in cases {
        let rate = high_entropy_detection_rate(alphabet, len, 2000);
        assert!(
            rate >= min_rate,
            "{name} len {len}: detection rate {rate:.4} below {min_rate}"
        );
    }
}

fn high_entropy_values(text: &str) -> Vec<String> {
    DetectionEngine::scan(&DetectionRequest::new(text))
        .entities
        .into_iter()
        .filter(|e| e.entity_type == EntityType::HighEntropyString)
        .map(|e| e.value)
        .collect()
}

#[test]
fn symbol_secret_detects_issue_clipboard_example() {
    // Issue #57: random string with special characters copied on its own.
    let secret = "Zq8$Lm3!Xv7#Rt2@Yb9%Kp4^Wn6&Hc1*Jd5(Fs0)Ga";
    assert_eq!(high_entropy_values(secret), vec![secret.to_string()]);
    assert_eq!(high_entropy_values(&format!("{secret}\n")), vec![secret.to_string()]);
}

#[test]
fn symbol_secret_detects_password_on_its_own_line() {
    let secret = "Zq8$Lm3!Xv7#Rt2@";
    let cases = [
        format!("login: bob\n{secret}\nthanks"),
        format!("notes\n    {secret}\n"),
        format!("notes\r\n{secret}\r\nmore"),
        format!("{secret}   \nnext line"),
        format!("first\n\t{secret}"),
    ];
    for text in cases {
        assert_eq!(high_entropy_values(&text), vec![secret.to_string()], "in {text:?}");
    }
}

#[test]
fn symbol_secret_needs_sixteen_characters() {
    assert!(high_entropy_values("Zq8$Lm3!Xv7#Rt2").is_empty());
    assert!(!high_entropy_values("Zq8$Lm3!Xv7#Rt2@").is_empty());
}

#[test]
fn symbol_secret_inside_prose_is_left_to_labeled_rules() {
    // Bare symbol tokens are only trusted when they fill the whole line; in prose
    // they are indistinguishable from code, so only `password: …` labels catch them.
    assert!(high_entropy_values("my new one is Zq8$Lm3!Xv7#Rt2@ ok").is_empty());
    assert!(!critical_secret_values("password: Zq8$Lm3!Xv7#Rt2@").is_empty());
}

#[test]
fn symbol_secret_ignores_issue_workaround_samples() {
    // From the reporter's custom-regex workaround table.
    for s in [
        "https://google.com/search?q=teszt1",
        "Dokumentum_2026-11.pdf",
        "nev.vezeteknev@gmail.com",
    ] {
        assert!(high_entropy_values(s).is_empty(), "unexpected highEntropyString in: {s}");
    }
}

#[test]
fn symbol_secret_ignores_standalone_code_and_data_lines() {
    let snippet = r#"
        ExitCode::from(1)
        Self(kVK_ANSI_Keypad0)
        Node(UInt16.max),
        perms.set_mode(0o755);
        items[0].price*qty2
        $XDG_DATA_DIRS[0]
        #[derive(Debug,Clone)]
        (?P<dev_n>[0-9]+)?
        [a-zA-Z0-9_-]{20,}
        <key>77FAE1A8-B98D-4B60-B1A8-B7CF93A8AAD9</key>
        <date>2026-06-12T15:50:47Z</date>
        45:14:0b:32:47:eb:9c:c8:c5:b4:f0:d7:b5:30:91:f7
        2026-11-07T10:23:00Z
        192.168.0.1:8080/health
        v1.2.3-beta.4+build.5
        certifi==2021.05.30
        ~/Library/Caches/offsend-1.2
        C:\Users\me\offsend2.exe
        user@example.com:22
        type[BaseExcT_1]:
        max_array_len=-1,
    "#;
    let values = high_entropy_values(snippet);
    assert!(values.is_empty(), "unexpected highEntropyString: {values:?}");
}

#[test]
fn symbol_line_rejection_keeps_base_alphabet_secret() {
    // The whole line fails the symbol filter (trailing `;`), but the 49-character
    // base62 run inside it is still judged by the base detector.
    let secret = "Zq8Lm3Xv7Rt2Yb9Kp4Wn6Hc1Jd5Fs0GaQe8UiO3Mx7Vz2NbT6";
    assert_eq!(high_entropy_values(&format!("{secret};")), vec![secret.to_string()]);
}

fn symbol_secret_detection_rate(alphabet: &str, symbols: &str, len: usize, samples: usize) -> f64 {
    let mut rng = XorShift(0xD1B5_4A32_D192_ED03);
    let mut tried = 0;
    let mut detected = 0;
    while tried < samples {
        let candidate = rng.string(alphabet.as_bytes(), len);
        let in_scope = candidate.chars().any(|c| c.is_ascii_alphabetic())
            && candidate.chars().any(|c| c.is_ascii_digit())
            && candidate.chars().any(|c| symbols.contains(c));
        if !in_scope {
            continue;
        }
        tried += 1;
        if detects_high_entropy(&candidate) {
            detected += 1;
        }
    }
    detected as f64 / samples as f64
}

#[test]
fn symbol_secret_detection_rate_on_generated_passwords() {
    const ALNUM: &str = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
    const PRINTABLE: &str = "!#$%&()*+,-./:;<=>?@[]^_{|}~";
    const COMMON: &str = "!@#$%^&*";
    let printable = format!("{ALNUM}{PRINTABLE}");
    let common = format!("{ALNUM}{COMMON}");
    for len in [16, 20, 24, 32] {
        for (name, alphabet, symbols) in [("printable", &printable, PRINTABLE), ("common", &common, COMMON)] {
            let rate = symbol_secret_detection_rate(alphabet, symbols, len, 1000);
            eprintln!("{name} len {len}: {rate:.3}");
            assert!(rate >= 0.85, "{name} len {len}: detection rate {rate:.3} below 0.85");
        }
    }
}

#[test]
fn secret_type_labels_are_specific() {
    assert_eq!(
        EntityType::OpenAIAPIKey.placeholder_prefix(),
        "OPENAI_API_KEY"
    );
    assert_eq!(EntityType::GithubToken.placeholder_prefix(), "GITHUB_TOKEN");
    assert_eq!(EntityType::Jwt.placeholder_prefix(), "JWT");
    assert_eq!(EntityType::ApiKeyGeneric.placeholder_prefix(), "SECRET");
}
