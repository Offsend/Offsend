from pathlib import Path
import sys

BENCH_ROOT = Path(__file__).resolve().parents[1]
REPO_ROOT = BENCH_ROOT.parents[1]
CASES_DIR = BENCH_ROOT / "cases"
SCHEMAS_DIR = BENCH_ROOT / "schemas"
REPORTS_DIR = BENCH_ROOT / "reports"
RESULTS_DIR = BENCH_ROOT / "results"
CACHE_DIR = BENCH_ROOT / ".cache"


def ensure_import_path() -> None:
    root = str(BENCH_ROOT)
    if root not in sys.path:
        sys.path.insert(0, root)
