from __future__ import annotations

import hashlib
import json
import random
import subprocess
import uuid
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import yaml

from graders import grade_response
from graders.security import grade_security, refusal_bucket
from providers import get_provider
from runners.cases import assert_corpus_quotas, load_cases
from runners.common import VARIANTS, utf8_sha256
from runners.config import BenchmarkConfig, load_benchmark_config
from runners.fixtures import load_fixture_catalog, materialize_catalog
from runners.offsend import ensure_benchmark_key, offsend_version, resolve_offsend_bin
from runners.paths import REPORTS_DIR, REPO_ROOT, RESULTS_DIR
from runners.preflight import run_preflight
from runners.prompt import render_v1
from runners.report import aggregate, write_reports
from runners.variants import MaterializedCase, materialize_case


def git_sha() -> str:
    proc = subprocess.run(
        ["git", "rev-parse", "HEAD"],
        cwd=REPO_ROOT,
        capture_output=True,
        text=True,
    )
    if proc.returncode != 0:
        raise RuntimeError("git_sha is required; run from a git checkout")
    return proc.stdout.strip()


def write_snapshot(
    config: BenchmarkConfig,
    dest: Path,
    *,
    offsend_ver: str | None,
    sha: str,
) -> None:
    snapshot = {
        "benchmark_version": config.benchmark_version,
        "prompt_template": config.prompt_template,
        "conversation_mode": config.conversation_mode,
        "runs_per_case": config.runs_per_case,
        "temperature": config.temperature,
        "models": [m.id for m in config.models],
        "runner_seed": config.runner_seed,
        "fixture_seed": config.fixture_seed,
        "git_sha": sha,
        "offsend_version": offsend_ver,
        "seal_token_version": config.seal_token_version,
    }
    dest.write_text(yaml.safe_dump(snapshot, sort_keys=False))


def prepare_corpus(
    config: BenchmarkConfig,
    offsend: Path,
    key_path: Path,
) -> tuple[list[MaterializedCase], list[tuple[str, str]]]:
    catalog = load_fixture_catalog()
    values = materialize_catalog(catalog, config.fixture_seed)
    cases = load_cases()
    assert_corpus_quotas(cases)
    admitted: list[MaterializedCase] = []
    dropped: list[tuple[str, str]] = []
    for case in cases:
        item = materialize_case(case, values, offsend, key_path)
        result = run_preflight(item)
        if result.ok:
            admitted.append(item)
        else:
            dropped.append((case.id, result.reason or "unknown"))
    return admitted, dropped


def variant_order(case_id: str, model: str, run: int, runner_seed: str) -> list[str]:
    material = f"{runner_seed}:{case_id}:{model}:{run}"
    seed_int = int(hashlib.sha256(material.encode("utf-8")).hexdigest()[:16], 16)
    order = list(VARIANTS)
    random.Random(seed_int).shuffle(order)
    return order


def grade_record(
    item: MaterializedCase,
    variant: str,
    response: str,
    offsend: Path,
) -> dict[str, Any]:
    case = item.case
    task = grade_response(case.grader["kind"], case.grader, response)
    security = grade_security(
        response,
        item.secrets,
        item.issued_tokens if variant == "offsend" else [],
        case.placeholder_eligible and variant == "offsend",
        offsend,
    )
    bucket = task["failure_bucket"]
    detail = task.get("failure_detail")
    if task["score"] == 0:
        refused = refusal_bucket(response, bucket)
        if refused:
            bucket = refused
            detail = "refusal_phrase"
    else:
        if security["fabricated_secret"]:
            bucket = "fabricated_secret"
            detail = "detector_finding_not_original_or_token"
        elif security["placeholder_bucket"]:
            bucket = security["placeholder_bucket"]
            detail = security["placeholder_bucket"]
        else:
            bucket = None
            detail = None
    return {
        "score": task["score"],
        "failure_bucket": bucket,
        "failure_detail": detail,
        **security,
    }


def run_evaluation(
    config: BenchmarkConfig,
    admitted: list[MaterializedCase],
    offsend: Path,
    run_dir: Path,
    *,
    models: list[str] | None = None,
) -> list[dict[str, Any]]:
    records: list[dict[str, Any]] = []
    raw_path = run_dir / "requests.jsonl"
    selected = [m for m in config.models if models is None or m.id in models]
    if not selected:
        raise ValueError("no models selected")

    with raw_path.open("w") as raw_file:
        for model in selected:
            provider = get_provider(model.provider)
            for item in admitted:
                for run in range(1, config.runs_per_case + 1):
                    order = variant_order(item.case.id, model.id, run, config.runner_seed)
                    for variant in order:
                        record = _one_request(
                            config=config,
                            item=item,
                            variant=variant,
                            variant_order_index=order.index(variant) + 1,
                            model=model.id,
                            provider_name=model.provider,
                            run=run,
                            provider=provider,
                            offsend=offsend,
                        )
                        records.append(record)
                        raw_file.write(json.dumps(record, ensure_ascii=False) + "\n")
                        raw_file.flush()
    return records


def _one_request(
    *,
    config: BenchmarkConfig,
    item: MaterializedCase,
    variant: str,
    variant_order_index: int,
    model: str,
    provider_name: str,
    run: int,
    provider,
    offsend: Path,
) -> dict[str, Any]:
    context = item.variants[variant]
    system, user = render_v1(item.case.task, context)
    completion = provider.complete(
        model=model,
        system=system,
        user=user,
        temperature=config.temperature,
        max_tokens=config.max_tokens,
    )
    graded = grade_record(item, variant, completion.text, offsend)
    secrets_out = [
        {
            "fixture": secret["fixture"],
            "value": secret["value"],
            "sha256": utf8_sha256(secret["value"]),
        }
        for secret in item.secrets
    ]
    return {
        "request_id": str(uuid.uuid4()),
        "case_id": item.case.id,
        "category": item.case.category,
        "variant": variant,
        "variant_order": variant_order_index,
        "provider": provider_name,
        "model": model,
        "model_version": completion.model_version,
        "prompt_template": config.prompt_template,
        "run": run,
        "fixture_seed": config.fixture_seed,
        "runner_seed": config.runner_seed,
        "prompt": f"{system}\n\n{user}",
        "context": context,
        "materialized_secrets": secrets_out,
        "issued_tokens": item.issued_tokens if variant == "offsend" else [],
        "response": completion.text,
        "score": graded["score"],
        "preflight": "ok",
        "leakage": graded["leakage"],
        "placeholder_preserved": graded["placeholder_preserved"],
        "fabricated_secret": graded["fabricated_secret"],
        "token_matches": graded["token_matches"],
        "expected_token_count": graded["expected_token_count"],
        "failure_bucket": graded["failure_bucket"],
        "failure_detail": graded.get("failure_detail"),
        "provider_request_id": completion.provider_request_id,
        "prompt_tokens": completion.prompt_tokens,
    }


def new_run_id() -> str:
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    return stamp


def prepare_run_dirs(run_id: str) -> tuple[Path, Path]:
    raw_dir = RESULTS_DIR / "raw" / run_id
    raw_dir.mkdir(parents=True, exist_ok=True)
    report_dir = REPORTS_DIR / run_id
    report_dir.mkdir(parents=True, exist_ok=True)
    return raw_dir, report_dir


def load_records(path: Path) -> list[dict[str, Any]]:
    records = []
    for line in path.read_text().splitlines():
        if line.strip():
            records.append(json.loads(line))
    return records
