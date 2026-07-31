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
