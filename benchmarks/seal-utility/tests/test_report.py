from runners.report import aggregate, enrich_failure_details, render_markdown, rescore_records


def _record(**overrides):
    rec = {
        "request_id": "req-1",
        "case_id": "postgres-config-001",
        "category": "config",
        "variant": "clean",
        "model": "gpt-4o-mini",
        "run": 1,
        "score": 1,
        "failure_bucket": None,
        "failure_detail": None,
        "leakage": False,
        "fabricated_secret": False,
        "placeholder_preserved": None,
        "response": "ok",
        "materialized_secrets": [
            {"fixture": "password_001", "value": "SYNTHETIC_SECRET_VALUE", "sha256": "abc"}
        ],
        "issued_tokens": [],
        "context": "x",
        "prompt_tokens": 10,
    }
    rec.update(overrides)
    return rec


def test_overall_clean_population_is_intersection():
    records = [
        _record(model="gpt-4o-mini", case_id="shared-001", score=1),
        _record(model="gpt-4o-mini", case_id="shared-001", variant="offsend", score=1),
        _record(model="claude-sonnet-4-5", case_id="shared-001", score=1),
        _record(model="claude-sonnet-4-5", case_id="shared-001", variant="offsend", score=1),
        _record(model="gpt-4o-mini", case_id="gpt-only-001", score=1),
        _record(model="gpt-4o-mini", case_id="gpt-only-001", variant="offsend", score=1),
        _record(
            model="claude-sonnet-4-5",
            case_id="gpt-only-001",
            score=0,
            failure_bucket="invalid_json",
            failure_detail="markdown_fence",
        ),
        _record(model="claude-sonnet-4-5", case_id="gpt-only-001", variant="offsend", score=0),
    ]
    diag = aggregate(records)["diagnostics"]
    assert diag["clean_population"]["overall"]["qualified"] == ["shared-001"]
    assert diag["clean_population"]["by_model"]["gpt-4o-mini"]["qualified"] == [
        "gpt-only-001",
        "shared-001",
    ]
    claude_excluded = diag["clean_population"]["by_model"]["claude-sonnet-4-5"]["excluded"]
    assert claude_excluded == [
        {
            "case_id": "gpt-only-001",
            "category": "config",
            "failure_bucket": "invalid_json",
            "failure_detail": "markdown_fence",
        }
    ]


def test_failure_preview_redacts_secrets_and_tokens():
    records = [
        _record(score=1),
        _record(
            variant="offsend",
            score=0,
            failure_bucket="invalid_json",
            failure_detail="markdown_fence",
            response="```json\npassword SYNTHETIC_SECRET_VALUE {{PASSWORD:v1.abc}}\n```",
            issued_tokens=["{{PASSWORD:v1.abc}}"],
        ),
    ]
    failures = aggregate(records)["diagnostics"]["failures"]
    assert len(failures) == 1
    preview = failures[0]["response_preview"]
    assert "SYNTHETIC_SECRET_VALUE" not in preview
    assert "{{PASSWORD:v1.abc}}" not in preview
    assert "[secret:password_001]" in preview
    assert "[seal-token]" in preview


def test_utility_losses_only_include_clean_pass_transformed_fails():
    records = [
        _record(case_id="keep-001", score=1),
        _record(
            case_id="keep-001",
            variant="delete",
            score=0,
            failure_bucket="wrong_field_interpretation",
            failure_detail="field_mismatch: host (got str, expected str)",
        ),
        _record(
            case_id="clean-fail-001",
            score=0,
            failure_bucket="invalid_json",
            failure_detail="markdown_fence",
        ),
        _record(
            case_id="clean-fail-001",
            variant="offsend",
            score=0,
            failure_bucket="invalid_json",
            failure_detail="markdown_fence",
        ),
    ]
    losses = aggregate(records)["diagnostics"]["utility_losses"]
    assert [row["case_id"] for row in losses] == ["keep-001"]
    assert losses[0]["variant"] == "delete"


def test_markdown_includes_diagnostics_without_secrets():
    records = [
        _record(score=1),
        _record(
            variant="offsend",
            score=0,
            failure_bucket="invalid_json",
            failure_detail="markdown_fence",
            response="leaked SYNTHETIC_SECRET_VALUE",
        ),
    ]
    md = render_markdown(aggregate(records))
    assert "## Diagnostics" in md
    assert "### Clean population" in md
    assert "### Utility losses" in md
    assert "### Failure log" in md
    assert "SYNTHETIC_SECRET_VALUE" not in md
    assert "[secret:password_001]" in md


def test_enrich_failure_details_from_stored_response():
    records = [
        _record(
            case_id="postgres-config-001",
            score=0,
            failure_bucket="invalid_json",
            failure_detail=None,
            response='Here you go:\n```json\n{"ok": true}\n```',
        )
    ]
    enrich_failure_details(records)
    assert records[0]["failure_detail"] == "markdown_fence"


def test_rescore_accepts_single_json_fence():
    records = [
        _record(
            case_id="postgres-config-001",
            score=0,
            failure_bucket="invalid_json",
            response=(
                '```json\n{"protocol":"postgres","username":"admin",'
                '"host":"db.internal","database":"prod","has_authentication":true}\n```'
            ),
        )
    ]
    rescore_records(records)
    assert records[0]["score"] == 1
    assert records[0]["failure_bucket"] is None
