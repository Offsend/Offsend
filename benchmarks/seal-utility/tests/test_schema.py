from runners.cases import assert_corpus_quotas, load_cases
from runners.config import load_benchmark_config
from runners.fixtures import load_fixture_catalog


def test_benchmark_and_cases_validate():
    config = load_benchmark_config()
    assert config.benchmark_version == "v0.1"
    assert config.prompt_template == "v1"
    assert config.conversation_mode == "stateless"
    assert len(config.models) >= 2
    load_fixture_catalog()
    cases = load_cases()
    assert_corpus_quotas(cases)
    assert len(cases) == 30
    assert sum(1 for case in cases if len(case.sensitive) >= 2) >= 5
