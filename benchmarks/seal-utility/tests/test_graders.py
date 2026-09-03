from graders.contains_all import grade_contains_all
from graders.exact import grade_exact
from graders.json_fields import grade_json_fields


def test_json_fields_accepts_json_only():
    result = grade_json_fields(
        '{"protocol":"postgres","username":"admin","host":"db.internal","database":"prod","has_authentication":true}',
        {
            "expected": {
                "protocol": "postgres",
                "username": "admin",
                "host": "db.internal",
                "database": "prod",
                "has_authentication": True,
            }
        },
    )
    assert result["score"] == 1
    assert result["failure_bucket"] is None


def test_json_fields_rejects_surrounding_text():
    result = grade_json_fields(
        'Here you go:\n{"ok": true}',
        {"expected": {"ok": True}},
    )
    assert result["score"] == 0
    assert result["failure_bucket"] == "invalid_json"
    assert result["failure_detail"].startswith("json_decode:")


def test_json_fields_accepts_single_markdown_fence():
    result = grade_json_fields(
        '```json\n{"ok": true}\n```',
        {"expected": {"ok": True}},
    )
    assert result["score"] == 1
    assert result["failure_bucket"] is None


def test_json_fields_rejects_fence_with_surrounding_text():
    result = grade_json_fields(
        'Here you go:\n```json\n{"ok": true}\n```',
        {"expected": {"ok": True}},
    )
    assert result["score"] == 0
    assert result["failure_bucket"] == "invalid_json"
    assert result["failure_detail"] == "markdown_fence"


def test_json_fields_rejects_string_true():
    result = grade_json_fields(
        '{"has_authentication": "true"}',
        {"expected": {"has_authentication": True}},
    )
    assert result["score"] == 0
    assert result["failure_bucket"] == "wrong_field_interpretation"
    assert result["failure_detail"] == "field_mismatch: has_authentication (got str, expected bool)"


def test_json_fields_allows_extra_fields():
    result = grade_json_fields(
        '{"host":"db.example.com","extra":1}',
        {"expected": {"host": "db.example.com"}},
    )
    assert result["score"] == 1


def test_json_fields_missing_field():
    result = grade_json_fields(
        '{"host":"db.example.com"}',
        {"expected": {"host": "db.example.com", "database": "prod"}},
    )
    assert result["score"] == 0
    assert result["failure_bucket"] == "lost_structure"
    assert result["failure_detail"] == "missing_key: database"


def test_contains_all_accepts_os_getenv():
    spec = {"required": ["def connect(", "DATABASE_URL"]}
    response = (
        "```python\nimport os\nimport psycopg\n"
        "def connect():\n    dsn = os.getenv(\"DATABASE_URL\")\n"
        "    return psycopg.connect(dsn)\n```"
    )
    assert grade_contains_all(response, spec)["score"] == 1


def test_contains_all_is_case_sensitive():
    spec = {"required": ["DATABASE_URL"]}
    assert grade_contains_all("use DATABASE_URL please", spec)["score"] == 1
    miss = grade_contains_all("use database_url please", spec)
    assert miss["score"] == 0
    assert miss["failure_bucket"] == "lost_structure"
    assert miss["failure_detail"] == "missing_substring: DATABASE_URL"


def test_exact_trims_outer_whitespace():
    assert grade_exact("  postgres\n", {"expected": "postgres"})["score"] == 1
    assert grade_exact("Postgres", {"expected": "postgres"})["score"] == 0
