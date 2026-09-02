from __future__ import annotations

import argparse
import sys
from pathlib import Path

_BENCH_ROOT = Path(__file__).resolve().parents[1]
if str(_BENCH_ROOT) not in sys.path:
    sys.path.insert(0, str(_BENCH_ROOT))


from runners.cases import assert_corpus_quotas, load_cases
from runners.config import load_benchmark_config
from runners.fixtures import load_fixture_catalog
from runners.offsend import ensure_benchmark_key, offsend_version, resolve_offsend_bin
from runners.paths import REPORTS_DIR
from runners.runner import (
    git_sha,
    load_records,
    new_run_id,
    prepare_corpus,
    prepare_run_dirs,
    run_evaluation,
    write_snapshot,
)
from runners.report import aggregate, rescore_records, write_reports


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="seal-utility")
    sub = parser.add_subparsers(dest="cmd", required=True)

    sub.add_parser("validate", help="Validate schemas and corpus quotas")

    pre = sub.add_parser("preflight", help="Materialize + preflight all cases (no LLM)")
    pre.add_argument("--offsend", default=None)

    run = sub.add_parser("run", help="Full stateless model evaluation")
    run.add_argument("--offsend", default=None)
    run.add_argument("--model", action="append", dest="models")
    run.add_argument("--run-id", default=None)

    report = sub.add_parser("report", help="Rebuild aggregate report from raw JSONL")
    report.add_argument("raw_jsonl", type=Path)
    report.add_argument(
        "--out",
        type=Path,
        default=None,
        help="Report directory (default: reports/<raw-parent-name>)",
    )

    args = parser.parse_args(argv)
    if args.cmd == "validate":
        return cmd_validate()
    if args.cmd == "preflight":
        return cmd_preflight(args.offsend)
    if args.cmd == "run":
        return cmd_run(args.offsend, args.models, args.run_id)
    if args.cmd == "report":
        return cmd_report(args.raw_jsonl, args.out)
    return 2


def cmd_validate() -> int:
    load_benchmark_config()
    load_fixture_catalog()
    cases = load_cases()
    assert_corpus_quotas(cases)
    print(f"ok: {len(cases)} cases, schema + quotas")
    return 0


def cmd_preflight(offsend_path: str | None) -> int:
    config = load_benchmark_config()
    offsend = resolve_offsend_bin(offsend_path)
    key = ensure_benchmark_key(offsend)
    admitted, dropped = prepare_corpus(config, offsend, key)
    for case_id, reason in dropped:
        print(f"FAIL {case_id}: {reason}", file=sys.stderr)
    print(f"admitted {len(admitted)} / {len(admitted) + len(dropped)}")
    if dropped:
        return 1
    if not admitted:
        print("no admitted cases", file=sys.stderr)
        return 1
    print("preflight ok")
    return 0


def cmd_run(offsend_path: str | None, models: list[str] | None, run_id: str | None) -> int:
    config = load_benchmark_config()
    offsend = resolve_offsend_bin(offsend_path)
    key = ensure_benchmark_key(offsend)
    admitted, dropped = prepare_corpus(config, offsend, key)
    if dropped:
        for case_id, reason in dropped:
            print(f"FAIL {case_id}: {reason}", file=sys.stderr)
        return 1
    run_id = run_id or new_run_id()
    raw_dir, report_dir = prepare_run_dirs(run_id)
    sha = git_sha()
    write_snapshot(
        config,
        raw_dir / "benchmark-config.snapshot.yaml",
        offsend_ver=offsend_version(offsend),
        sha=sha,
    )
    write_snapshot(
        config,
        report_dir / "benchmark-config.snapshot.yaml",
        offsend_ver=offsend_version(offsend),
        sha=sha,
    )
    records = run_evaluation(config, admitted, offsend, raw_dir, models=models)
    agg = aggregate(records)
    write_reports(agg, report_dir)
    print(f"raw: {raw_dir / 'requests.jsonl'}")
    print(f"report: {report_dir / 'report.md'}")
    if agg["overall"]["security_failure"]:
        print("SECURITY FAILURE — utility shown for diagnostics only", file=sys.stderr)
    return 0


def cmd_report(raw_jsonl: Path, dest: Path | None = None) -> int:
    records = rescore_records(load_records(raw_jsonl))
    agg = aggregate(records)
    dest = dest or (REPORTS_DIR / raw_jsonl.resolve().parent.name)
    write_reports(agg, dest)
    print(f"wrote {dest / 'report.md'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
