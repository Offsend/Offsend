from __future__ import annotations

V1_SYSTEM = "You are completing a benchmark task.\nFollow the requested output format exactly."


def render_v1(task: str, variant_context: str) -> tuple[str, str]:
    user = (
        "<TASK>\n"
        f"{task}\n"
        "</TASK>\n"
        "\n"
        "<CONTEXT>\n"
        f"{variant_context}\n"
        "</CONTEXT>"
    )
    return V1_SYSTEM, user
