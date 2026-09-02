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
fn secret_type_labels_are_specific() {
    assert_eq!(
        EntityType::OpenAIAPIKey.placeholder_prefix(),
        "OPENAI_API_KEY"
    );
    assert_eq!(EntityType::GithubToken.placeholder_prefix(), "GITHUB_TOKEN");
    assert_eq!(EntityType::Jwt.placeholder_prefix(), "JWT");
    assert_eq!(EntityType::ApiKeyGeneric.placeholder_prefix(), "SECRET");
}
