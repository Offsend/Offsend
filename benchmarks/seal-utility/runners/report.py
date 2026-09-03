from __future__ import annotations

import json
from collections import Counter, defaultdict
from pathlib import Path
from typing import Any

from runners.common import TRANSFORMED_VARIANTS, VARIANTS

PREVIEW_LIMIT = 200

VARIANT_LABEL = {
    "clean": "Clean",
    "offsend": "Offsend",
    "redacted": "[REDACTED]",
    "delete": "Delete",
}


def aggregate(records: list[dict[str, Any]]) -> dict[str, Any]:
    by_model: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for rec in records:
        by_model[rec["model"]].append(rec)

    models = {}
    for model, items in by_model.items():
        models[model] = _aggregate_model(items)

    overall_records = records
    return {
        "overall": _aggregate_model(overall_records) if overall_records else _empty_model(),
        "by_model": models,
        "by_category": _by_category(records),
        "failure_buckets": dict(Counter(r["failure_bucket"] for r in records if r.get("failure_bucket"))),
        "admitted_case_ids": sorted({r["case_id"] for r in records}),
        "diagnostics": _diagnostics(records),
    }


def _aggregate_model(records: list[dict[str, Any]]) -> dict[str, Any]:
    admitted = sorted({r["case_id"] for r in records})
    clean_pass = _clean_pass_ids(records)
    excluded = [cid for cid in admitted if cid not in clean_pass]

    tsr = {}
    plr = {}
    ppr = {}
    for variant in VARIANTS:
        subset = [r for r in records if r["variant"] == variant]
        tsr[variant] = _mean_score(subset)
        if variant != "clean":
            plr[variant] = _rate(subset, "leakage")
        eligible = [r for r in subset if r.get("placeholder_preserved") is not None]
        if variant == "offsend" and eligible:
            matches = sum(r.get("token_matches") or 0 for r in eligible)
            expected = sum(r.get("expected_token_count") or 0 for r in eligible)
            ppr[variant] = (matches / expected) if expected else None
        else:
            ppr[variant] = None

    sur = {}
    for variant in VARIANTS:
        subset = [r for r in records if r["variant"] == variant and r["case_id"] in clean_pass]
        sur[variant] = _mean_score(subset) if subset else None

    inflation = _inflation(records)
    security_failure = any((plr.get(v) or 0) > 0 for v in TRANSFORMED_VARIANTS)

    return {
        "admitted": len(admitted),
        "clean_qualified": len(clean_pass),
        "excluded_because_clean_failed": len(excluded),
        "tsr": tsr,
        "sur": sur,
        "plr": plr,
        "ppr": ppr.get("offsend"),
        "char_inflation": inflation["offsend_char"],
        "prompt_token_inflation": inflation["offsend_token"],
        "char_inflation_by_variant": inflation["char_by_variant"],
        "token_inflation_by_variant": inflation["token_by_variant"],
        "security_failure": security_failure,
        "fsr": _rate([r for r in records if r["variant"] != "clean"], "fabricated_secret"),
    }


def _clean_pass_ids(records: list[dict[str, Any]]) -> set[str]:
    by_case: dict[str, list[int]] = defaultdict(list)
    for rec in records:
        if rec["variant"] == "clean":
            by_case[rec["case_id"]].append(int(rec["score"]))
    return {cid for cid, scores in by_case.items() if scores and all(s == 1 for s in scores)}


def _by_category(records: list[dict[str, Any]]) -> dict[str, Any]:
    groups: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for rec in records:
        groups[rec["category"]].append(rec)
    return {cat: _aggregate_model(items) for cat, items in sorted(groups.items())}


def _inflation(records: list[dict[str, Any]]) -> dict[str, Any]:
    char_acc: dict[str, list[float]] = {"offsend": [], "delete": [], "redacted": []}
    token_acc: dict[str, list[float]] = {"offsend": [], "delete": [], "redacted": []}
    by_key: dict[tuple[str, str, int], dict[str, dict[str, Any]]] = defaultdict(dict)
    for rec in records:
        key = (rec["model"], rec["case_id"], rec["run"])
        by_key[key][rec["variant"]] = rec
    for pair in by_key.values():
        redacted = pair.get("redacted")
        if not redacted:
            continue
        red_len = len(redacted.get("context") or "")
        red_tok = redacted.get("prompt_tokens")
        for variant in ("offsend", "delete", "redacted"):
            other = pair.get(variant)
            if not other or not red_len:
                continue
            char_acc[variant].append(len(other.get("context") or "") / red_len)
            other_tok = other.get("prompt_tokens")
            if isinstance(red_tok, int) and red_tok > 0 and isinstance(other_tok, int):
                token_acc[variant].append(other_tok / red_tok)
    return {
        "offsend_char": _avg(char_acc["offsend"]),
        "offsend_token": _avg(token_acc["offsend"]),
        "char_by_variant": {k: _avg(v) for k, v in char_acc.items()},
        "token_by_variant": {k: _avg(v) for k, v in token_acc.items()},
    }


def _avg(values: list[float]) -> float | None:
    return (sum(values) / len(values)) if values else None


def _mean_score(records: list[dict[str, Any]]) -> float | None:
    if not records:
        return None
    return sum(int(r["score"]) for r in records) / len(records)


def _rate(records: list[dict[str, Any]], field: str) -> float | None:
    if not records:
        return None
    return sum(1 for r in records if r.get(field)) / len(records)


def _empty_model() -> dict[str, Any]:
    return {
        "admitted": 0,
        "clean_qualified": 0,
        "excluded_because_clean_failed": 0,
        "tsr": {},
        "sur": {},
        "plr": {},
        "ppr": None,
        "char_inflation": None,
        "prompt_token_inflation": None,
        "char_inflation_by_variant": {},
        "token_inflation_by_variant": {},
        "security_failure": False,
        "fsr": None,
    }


def render_markdown(agg: dict[str, Any], *, model: str | None = None) -> str:
    block = agg["by_model"][model] if model else agg["overall"]
    return "\n".join(
        [
            "# Offsend seal-utility benchmark v0.1",
            "",
            "## All-cases performance",
            "",
            _all_cases_table(block),
            "",
            "## Primary utility — clean-qualified population",
            "",
            _primary_table(block),
            "",
            f"Excluded because clean failed: {block['excluded_because_clean_failed']} / {block['admitted']}",
            "",
            _security_status(block),
            "",
            "## Breakdown by category",
            "",
            _category_tables(agg["by_category"]),
            "",
            "## Breakdown by model",
            "",
            _model_tables(agg["by_model"]),
            "",
            "## Failure buckets",
            "",
            _bucket_list(agg["failure_buckets"]),
            "",
            "## Diagnostics",
            "",
            _diagnostics_markdown(agg["diagnostics"]),
            "",
        ]
    )


def rescore_records(records: list[dict[str, Any]]) -> list[dict[str, Any]]:
    """Re-apply current graders to stored responses. Does not rewrite raw JSONL."""
    from graders import grade_response
    from graders.security import refusal_bucket
    from runners.cases import load_cases

    cases = {case.id: case for case in load_cases()}
    for rec in records:
        case = cases.get(rec.get("case_id"))
        if case is None:
            continue
        task = grade_response(case.grader["kind"], case.grader, rec.get("response") or "")
        bucket = task["failure_bucket"]
        detail = task.get("failure_detail")
        if task["score"] == 0:
            refused = refusal_bucket(rec.get("response") or "", bucket)
            if refused:
                bucket = refused
                detail = "refusal_phrase"
        elif rec.get("fabricated_secret"):
            bucket = "fabricated_secret"
            detail = "detector_finding_not_original_or_token"
        elif rec.get("placeholder_preserved") is False:
            bucket = rec.get("failure_bucket") or "placeholder_removed"
            detail = bucket
        else:
            bucket = None
            detail = None
        rec["score"] = task["score"]
        rec["failure_bucket"] = bucket
        rec["failure_detail"] = detail
    return records


def enrich_failure_details(records: list[dict[str, Any]]) -> list[dict[str, Any]]:
    return rescore_records(records)


def write_reports(agg: dict[str, Any], dest: Path) -> None:
    dest.mkdir(parents=True, exist_ok=True)
    (dest / "report.json").write_text(json.dumps(agg, indent=2) + "\n")
    (dest / "report.md").write_text(render_markdown(agg))


def _pct(value: float | None) -> str:
    if value is None:
        return "—"
    return f"{value * 100:.1f}%".replace(".0%", "%")


def _num(value: float | None) -> str:
    if value is None:
        return "—"
    return f"{value:.2f}"


def _all_cases_table(block: dict[str, Any]) -> str:
    lines = [
        "| Variant | TSR | Output leakage (PLR) | Placeholder preservation | Char inflation | Prompt-token inflation |",
        "|---|---:|---:|---:|---:|---:|",
    ]
    for variant in VARIANTS:
        plr = "—" if variant == "clean" else _pct(block["plr"].get(variant))
        ppr = _pct(block["ppr"]) if variant == "offsend" else "—"
        char = "—" if variant == "clean" else _num((block.get("char_inflation_by_variant") or {}).get(variant))
        token = "—" if variant == "clean" else _num((block.get("token_inflation_by_variant") or {}).get(variant))
        lines.append(
            f"| {VARIANT_LABEL[variant]} | {_pct(block['tsr'].get(variant))} | {plr} | {ppr} | {char} | {token} |"
        )
    return "\n".join(lines)


def _primary_table(block: dict[str, Any]) -> str:
    n = block["clean_qualified"]
    lines = [
        "| Variant | SUR | Clean-qualified cases |",
        "|---|---:|---:|",
    ]
    for variant in VARIANTS:
        lines.append(f"| {VARIANT_LABEL[variant]} | {_pct(block['sur'].get(variant))} | {n} |")
    return "\n".join(lines)


def _security_status(block: dict[str, Any]) -> str:
    lines = ["Security status:"]
    for variant in TRANSFORMED_VARIANTS:
        label = VARIANT_LABEL[variant]
        lines.append(f"  {label} PLR = {_pct(block['plr'].get(variant))}")
    if block["security_failure"]:
        lines.append("")
        lines.append("SECURITY FAILURE — utility shown for diagnostics only")
    return "\n".join(lines)


def _category_tables(by_category: dict[str, Any]) -> str:
    chunks = []
    for category, block in by_category.items():
        chunks.append(f"### {category}")
        chunks.append("")
        chunks.append(_primary_table(block))
        chunks.append("")
    return "\n".join(chunks).rstrip()


def _model_tables(by_model: dict[str, Any]) -> str:
    chunks = []
    for model, block in by_model.items():
        chunks.append(f"### {model}")
        chunks.append("")
        chunks.append(_all_cases_table(block))
        chunks.append("")
        chunks.append(_primary_table(block))
        chunks.append("")
        chunks.append(
            f"Excluded because clean failed: {block['excluded_because_clean_failed']} / {block['admitted']}"
        )
        chunks.append("")
        chunks.append(_security_status(block))
        chunks.append("")
    return "\n".join(chunks).rstrip()


def _bucket_list(buckets: dict[str, int]) -> str:
    if not buckets:
        return "None."
    return "\n".join(f"- `{name}`: {count}" for name, count in sorted(buckets.items()))


def _diagnostics(records: list[dict[str, Any]]) -> dict[str, Any]:
    by_model: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for rec in records:
        by_model[rec["model"]].append(rec)

    by_model_pop = {}
    for model, items in sorted(by_model.items()):
        admitted = sorted({r["case_id"] for r in items})
        qualified = sorted(_clean_pass_ids(items))
        by_model_pop[model] = {
            "qualified": qualified,
            "excluded": _excluded_clean(items, admitted, set(qualified)),
        }

    overall_admitted = sorted({r["case_id"] for r in records})
    overall_qualified = sorted(_clean_pass_ids(records))
    overall_excluded = []
    for case_id in overall_admitted:
        if case_id in overall_qualified:
            continue
        failed_models = []
        category = ""
        for model, pop in by_model_pop.items():
            excluded_ids = {row["case_id"] for row in pop["excluded"]}
            if case_id in excluded_ids:
                failed_models.append(model)
            elif case_id not in pop["qualified"]:
                failed_models.append(model)
        for rec in records:
            if rec["case_id"] == case_id:
                category = rec.get("category") or ""
                break
        overall_excluded.append(
            {"case_id": case_id, "category": category, "models_failed": failed_models}
        )

    failures = [_failure_entry(rec) for rec in records if _is_logged(rec)]
    failures.sort(key=lambda row: (row["model"], row["category"], row["case_id"], row["variant"], row["run"]))

    losses = []
    for model, items in sorted(by_model.items()):
        qualified = _clean_pass_ids(items)
        for rec in items:
            if rec["case_id"] not in qualified:
                continue
            if rec["variant"] == "clean":
                continue
            if int(rec.get("score") or 0) == 1 and not rec.get("leakage") and not rec.get("fabricated_secret"):
                continue
            losses.append(_failure_entry(rec))
    losses.sort(key=lambda row: (row["model"], row["category"], row["case_id"], row["variant"], row["run"]))

    bucket_rows = Counter(
        (rec.get("failure_bucket") or "unspecified", rec["model"], rec["variant"])
        for rec in records
        if rec.get("failure_bucket")
    )
    bucket_by_model_variant = [
        {"bucket": bucket, "model": model, "variant": variant, "count": count}
        for (bucket, model, variant), count in sorted(bucket_rows.items())
    ]

    return {
        "clean_population": {
            "overall": {"qualified": overall_qualified, "excluded": overall_excluded},
            "by_model": by_model_pop,
        },
        "utility_losses": losses,
        "failures": failures,
        "bucket_by_model_variant": bucket_by_model_variant,
    }


def _excluded_clean(
    records: list[dict[str, Any]],
    admitted: list[str],
    qualified: set[str],
) -> list[dict[str, Any]]:
    clean_by_case: dict[str, list[dict[str, Any]]] = defaultdict(list)
    category_by_case: dict[str, str] = {}
    for rec in records:
        category_by_case[rec["case_id"]] = rec.get("category") or ""
        if rec["variant"] == "clean":
            clean_by_case[rec["case_id"]].append(rec)
    rows = []
    for case_id in admitted:
        if case_id in qualified:
            continue
        cleans = clean_by_case.get(case_id) or []
        failed = [rec for rec in cleans if int(rec.get("score") or 0) == 0]
        sample = failed[0] if failed else (cleans[0] if cleans else None)
        rows.append(
            {
                "case_id": case_id,
                "category": category_by_case.get(case_id, ""),
                "failure_bucket": (sample or {}).get("failure_bucket"),
                "failure_detail": (sample or {}).get("failure_detail"),
            }
        )
    return rows


def _is_logged(rec: dict[str, Any]) -> bool:
    if rec.get("variant") == "clean":
        return int(rec.get("score") or 0) == 0
    return (
        int(rec.get("score") or 0) == 0
        or bool(rec.get("leakage"))
        or bool(rec.get("fabricated_secret"))
    )


def _failure_entry(rec: dict[str, Any]) -> dict[str, Any]:
    return {
        "request_id": rec.get("request_id"),
        "model": rec["model"],
        "case_id": rec["case_id"],
        "category": rec.get("category") or "",
        "variant": rec["variant"],
        "run": rec.get("run") or 1,
        "score": int(rec.get("score") or 0),
        "failure_bucket": rec.get("failure_bucket"),
        "failure_detail": rec.get("failure_detail"),
        "leakage": bool(rec.get("leakage")),
        "placeholder_preserved": rec.get("placeholder_preserved"),
        "response_preview": _response_preview(rec),
    }


def _response_preview(rec: dict[str, Any]) -> str:
    text = rec.get("response") or ""
    for secret in rec.get("materialized_secrets") or []:
        value = secret.get("value")
        if value:
            fixture = secret.get("fixture") or "redacted"
            text = text.replace(value, f"[secret:{fixture}]")
    for token in rec.get("issued_tokens") or []:
        if token:
            text = text.replace(token, "[seal-token]")
    text = " ".join(text.split())
    if len(text) > PREVIEW_LIMIT:
        text = text[: PREVIEW_LIMIT - 1] + "…"
    return text


def _diagnostics_markdown(diag: dict[str, Any]) -> str:
    chunks = [
        "Overall SUR uses cases that passed clean on every model in the run (intersection). "
        "Per-model SUR uses that model's own clean-pass list. "
        "Previews are sanitized; full prompts, responses, and secret values stay in `results/raw/`.",
        "",
        "### Clean population",
        "",
    ]
    pop = diag.get("clean_population") or {}
    for model, block in (pop.get("by_model") or {}).items():
        chunks.append(f"#### {model}")
        chunks.append("")
        chunks.append(_id_list("Qualified", block.get("qualified") or []))
        chunks.append("")
        chunks.append(_excluded_list(block.get("excluded") or []))
        chunks.append("")
    overall = pop.get("overall") or {}
    chunks.append("#### overall (intersection)")
    chunks.append("")
    chunks.append(_id_list("Qualified", overall.get("qualified") or []))
    chunks.append("")
    chunks.append(_overall_excluded_list(overall.get("excluded") or []))
    chunks.append("")
    chunks.append("### Utility losses")
    chunks.append("")
    chunks.append(
        "Clean passed for this model; a transformed variant failed or leaked. "
        "These rows are the primary signal for case/grader/seal changes."
    )
    chunks.append("")
    chunks.append(_event_table(diag.get("utility_losses") or []))
    chunks.append("")
    chunks.append("### Failure log")
    chunks.append("")
    chunks.append(_event_table(diag.get("failures") or []))
    chunks.append("")
    chunks.append("### Buckets by model × variant")
    chunks.append("")
    chunks.append(_bucket_matrix(diag.get("bucket_by_model_variant") or []))
    return "\n".join(chunks).rstrip()


def _id_list(label: str, ids: list[str]) -> str:
    if not ids:
        return f"{label} (0): none"
    joined = ", ".join(f"`{cid}`" for cid in ids)
    return f"{label} ({len(ids)}): {joined}"


def _excluded_list(rows: list[dict[str, Any]]) -> str:
    if not rows:
        return "Excluded (0): none"
    lines = [f"Excluded ({len(rows)}):"]
    for row in rows:
        detail = row.get("failure_detail")
        suffix = f" — `{row.get('failure_bucket')}`"
        if detail:
            suffix += f": {detail}"
        lines.append(f"- `{row['case_id']}` ({row.get('category') or '?'}){suffix}")
    return "\n".join(lines)


def _overall_excluded_list(rows: list[dict[str, Any]]) -> str:
    if not rows:
        return "Excluded (0): none"
    lines = [f"Excluded ({len(rows)}):"]
    for row in rows:
        models = ", ".join(row.get("models_failed") or []) or "?"
        lines.append(f"- `{row['case_id']}` ({row.get('category') or '?'}) — failed clean on: {models}")
    return "\n".join(lines)


def _event_table(rows: list[dict[str, Any]]) -> str:
    if not rows:
        return "None."
    lines = [
        "| Model | Case | Category | Variant | Bucket | Detail | Preview |",
        "|---|---|---|---|---|---|---|",
    ]
    for row in rows:
        lines.append(
            "| "
            + " | ".join(
                [
                    _cell(row.get("model")),
                    f"`{_cell(row.get('case_id'))}`",
                    _cell(row.get("category")),
                    _cell(row.get("variant")),
                    f"`{_cell(row.get('failure_bucket'))}`" if row.get("failure_bucket") else "—",
                    _cell(row.get("failure_detail")) or "—",
                    _cell(row.get("response_preview")) or "—",
                ]
            )
            + " |"
        )
    return "\n".join(lines)


def _bucket_matrix(rows: list[dict[str, Any]]) -> str:
    if not rows:
        return "None."
    lines = [
        "| Bucket | Model | Variant | Count |",
        "|---|---|---|---:|",
    ]
    for row in rows:
        lines.append(
            f"| `{_cell(row['bucket'])}` | {_cell(row['model'])} | {_cell(row['variant'])} | {row['count']} |"
        )
    return "\n".join(lines)


def _cell(value: Any) -> str:
    if value is None:
        return ""
    return str(value).replace("|", "\\|").replace("\n", " ")
