from runners.prompt import V1_SYSTEM, render_v1


def test_prompt_template_v1_is_canonical():
    system, user = render_v1("Do the task.", "context-body")
    assert system == V1_SYSTEM
    assert user == (
        "<TASK>\n"
        "Do the task.\n"
        "</TASK>\n"
        "\n"
        "<CONTEXT>\n"
        "context-body\n"
        "</CONTEXT>"
    )
    assert "You are completing a benchmark task." in system
    assert "Agent" not in system
