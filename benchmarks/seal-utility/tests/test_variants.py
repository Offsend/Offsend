from runners.common import utf8_sha256
from runners.variants import generate_delete, generate_redacted


def test_delete_is_minimum_span():
    text = "DATABASE_URL=postgres://admin:secret-value@db.internal/prod"
    secrets = [{"value": "secret-value", "fixture": "password_001", "type": "password"}]
    assert generate_delete(text, secrets) == "DATABASE_URL=postgres://admin:@db.internal/prod"


def test_redacted_replaces_only_listed_span():
    text = "DATABASE_URL=postgres://admin:secret-value@db.internal/prod"
    secrets = [{"value": "secret-value", "fixture": "password_001", "type": "password"}]
    assert generate_redacted(text, secrets) == (
        "DATABASE_URL=postgres://admin:[REDACTED]@db.internal/prod"
    )


def test_sha256_is_raw_utf8():
    assert utf8_sha256("abc") == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
    assert utf8_sha256(" abc") != utf8_sha256("abc")
