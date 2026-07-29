//! Loads corpus/seal golden vectors and asserts Rust open() matches Swift fixtures.

use offsend_seal::SealEngine;
use std::path::PathBuf;

#[test]
fn corpus_swift_legacy_vectors() {
    let path = corpus_path();
    let raw = std::fs::read_to_string(&path)
        .unwrap_or_else(|e| panic!("read {}: {e}", path.display()));
    let doc: serde_json::Value = serde_json::from_str(&raw).expect("parse golden json");
    let vectors = doc["vectors"].as_array().expect("vectors array");
    assert!(!vectors.is_empty());

    for v in vectors {
        let key_hex = v["key_hex"].as_str().unwrap();
        let token = v["token"].as_str().unwrap();
        let expected_type = v["type"].as_str().unwrap();
        let expected_plain = v["plaintext"].as_str().unwrap();
        let key = hex::decode(key_hex).expect("key hex");
        let engine = SealEngine::new(&key).unwrap();
        let (ty, plain) = engine.open(token).unwrap_or_else(|e| {
            panic!("open failed for {}: {e}", v["id"]);
        });
        assert_eq!(ty, expected_type);
        assert_eq!(plain, expected_plain);

        // Rust re-seal must unseal under the same key (fresh nonce).
        let resealed = engine.seal_value(&plain, &ty).unwrap();
        assert_eq!(engine.open(&resealed).unwrap().1, expected_plain);
    }
}

fn corpus_path() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("../../corpus/seal/v1-golden.json")
}
