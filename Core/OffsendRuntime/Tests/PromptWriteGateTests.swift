import XCTest
@testable import OffsendRuntime

final class PromptWriteGateTests: XCTestCase {
    private var root: URL!
    private var classifier: ExecutableArtifactClassifier!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent(".git/hooks", isDirectory: true),
            withIntermediateDirectories: true
        )
        classifier = ExecutableArtifactClassifier(
            projectRoot: root,
            gitResolver: GitRepositoryResolver(gitExecutable: "/nonexistent/git")
        )
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testParsesClaudeWritePayload() throws {
        let input = try PromptWriteGate.parse(
            json: """
            {
              "tool_name": "Write",
              "cwd": "\(root.path)",
              "tool_input": {
                "file_path": ".cursor/hooks.json",
                "content": "{\\"hooks\\":{}}"
              }
            }
            """,
            adapter: .claude
        )

        XCTAssertEqual(input.toolName, "Write")
        XCTAssertEqual(input.path, root.appendingPathComponent(".cursor/hooks.json").path)
        XCTAssertEqual(input.content, #"{"hooks":{}}"#)
    }

    func testParsesCursorEditPayload() throws {
        let input = try PromptWriteGate.parse(
            json: """
            {
              "tool_name": "Edit",
              "cwd": "\(root.path)",
              "tool_input": {
                "file_path": ".vscode/tasks.json",
                "new_string": "changed"
              }
            }
            """,
            adapter: .cursor
        )

        XCTAssertEqual(input.toolName, "Edit")
        XCTAssertEqual(input.content, "changed")
    }

    func testDeniesExecutableConfiguration() throws {
        let input = PromptWriteGateInput(
            toolName: "Write",
            path: root.appendingPathComponent(".claude/settings.local.json").path,
            content: "{}"
        )

        let decision = PromptWriteGate.evaluate(input: input, classifier: classifier)

        XCTAssertFalse(decision.allowed)
        XCTAssertEqual(decision.artifact?.kind, .editorHookConfig)
    }

    func testDeniesShellStartupConfiguration() {
        let input = PromptWriteGateInput(
            toolName: "Write",
            path: root.appendingPathComponent(".envrc").path,
            content: "export PATH=./bin:$PATH"
        )

        let decision = PromptWriteGate.evaluate(input: input, classifier: classifier)

        XCTAssertFalse(decision.allowed)
        XCTAssertEqual(decision.artifact?.kind, .shellStartupConfig)
    }

    func testAllowsOrdinarySourceFile() {
        let input = PromptWriteGateInput(
            toolName: "Write",
            path: root.appendingPathComponent("Sources/App.swift").path,
            content: "print(\"ok\")"
        )

        XCTAssertTrue(PromptWriteGate.evaluate(input: input, classifier: classifier).allowed)
    }

    func testAllowsObserveOnlyVenvInterpreter() {
        let input = PromptWriteGateInput(
            toolName: "Write",
            path: root.appendingPathComponent(".venv/bin/python").path,
            content: nil
        )

        let decision = PromptWriteGate.evaluate(input: input, classifier: classifier)

        XCTAssertTrue(decision.allowed)
        XCTAssertEqual(decision.artifact?.enforcement, .observe)
    }

    func testAllowsOrdinaryEditorSettingsButDeniesExecutableKeys() {
        let path = root.appendingPathComponent(".vscode/settings.json").path

        let ordinary = PromptWriteGate.evaluate(
            input: PromptWriteGateInput(
                toolName: "Write",
                path: path,
                content: #"{"editor.tabSize": 2, "files.trimTrailingWhitespace": true}"#
            ),
            classifier: classifier
        )
        XCTAssertTrue(ordinary.allowed)

        let executable = PromptWriteGate.evaluate(
            input: PromptWriteGateInput(
                toolName: "Write",
                path: path,
                content: #"{"editor.tabSize": 2, "python.defaultInterpreterPath": "/tmp/py"}"#
            ),
            classifier: classifier
        )
        XCTAssertEqual(executable.permission, .deny)
    }

    func testDeniesTerminalProfileInjectionFromEditFragment() {
        let decision = PromptWriteGate.evaluate(
            input: PromptWriteGateInput(
                toolName: "Edit",
                path: root.appendingPathComponent(".vscode/settings.json").path,
                content: #""terminal.integrated.env.osx": { "PATH": "/tmp/bin:${env:PATH}" }"#
            ),
            classifier: classifier
        )

        XCTAssertEqual(decision.permission, .deny)
    }

    func testDeniesEditThatOnlySwapsTheValueOfAnExecutableKey() throws {
        let path = try writeSettings(
            #"{"editor.tabSize": 2, "python.defaultInterpreterPath": "/usr/bin/python3"}"#
        )

        let decision = PromptWriteGate.evaluate(
            input: PromptWriteGateInput(
                toolName: "Edit",
                path: path,
                content: "/workspace/.agent-bin/python",
                replacedTexts: ["/usr/bin/python3"]
            ),
            classifier: classifier
        )

        XCTAssertEqual(decision.permission, .deny)
    }

    func testAllowsEditThatOnlySwapsTheValueOfAnOrdinaryKey() throws {
        let path = try writeSettings(
            #"{"editor.tabSize": 2, "python.defaultInterpreterPath": "/usr/bin/python3"}"#
        )

        let decision = PromptWriteGate.evaluate(
            input: PromptWriteGateInput(
                toolName: "Edit",
                path: path,
                content: "4",
                replacedTexts: ["2"]
            ),
            classifier: classifier
        )

        XCTAssertTrue(decision.allowed)
    }

    func testDeniesValueEditInSettingsFileThatCarriesComments() throws {
        let path = try writeSettings(
            """
            {
              // project defaults
              "editor.tabSize": 2,
              "terminal.integrated.automationProfile.osx": { "path": "/bin/zsh" }
            }
            """
        )

        let decision = PromptWriteGate.evaluate(
            input: PromptWriteGateInput(
                toolName: "Edit",
                path: path,
                content: "/workspace/.agent-bin/zsh",
                replacedTexts: ["/bin/zsh"]
            ),
            classifier: classifier
        )

        XCTAssertEqual(decision.permission, .deny)
    }

    func testAllowsValueEditWhenTheSettingsFileIsUnreadable() {
        let decision = PromptWriteGate.evaluate(
            input: PromptWriteGateInput(
                toolName: "Edit",
                path: root.appendingPathComponent(".vscode/settings.json").path,
                content: "/workspace/.agent-bin/python",
                replacedTexts: ["/usr/bin/python3"]
            ),
            classifier: classifier
        )

        XCTAssertTrue(decision.allowed)
    }

    private func writeSettings(_ contents: String) throws -> String {
        let url = root.appendingPathComponent(".vscode/settings.json")
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url.path
    }

    func testAsksWhenContentConditionalChangeHasNoContent() {
        let decision = PromptWriteGate.evaluate(
            input: PromptWriteGateInput(
                toolName: "Edit",
                path: root.appendingPathComponent("team.code-workspace").path,
                content: nil
            ),
            classifier: classifier
        )

        XCTAssertEqual(decision.permission, .ask)
    }

    func testUnrecognizedPayloadAsksOnClaudeAndBlocksOnCursor() {
        for decision in [PromptWriteGate.invalidInputDecision(), PromptWriteGate.oversizedInputDecision()] {
            XCTAssertEqual(decision.permission, .ask)
            XCTAssertTrue(
                PromptWriteGateRenderer.render(decision: decision, adapter: .claude)
                    .stdout.contains(#""permissionDecision":"ask""#)
            )
            // Cursor accepts `ask` on preToolUse but does not enforce it, so
            // rendering it verbatim would silently allow the write.
            let cursor = PromptWriteGateRenderer.render(decision: decision, adapter: .cursor).stdout
            XCTAssertTrue(cursor.contains(#""permission":"deny""#))
            XCTAssertTrue(cursor.contains("cannot ask for confirmation"))
        }
    }

    func testStrongestDecisionWinsAcrossTargets() {
        let decision = PromptWriteGate.evaluate(
            input: PromptWriteGateInput(
                toolName: "Delete",
                paths: [
                    root.appendingPathComponent("README.md").path,
                    root.appendingPathComponent(".envrc").path,
                ],
                content: nil
            ),
            classifier: classifier
        )

        XCTAssertEqual(decision.permission, .deny)
        XCTAssertEqual(decision.artifact?.kind, .shellStartupConfig)
    }

    func testRendererDeniesExecutableConfiguration() {
        let decision = PromptWriteGate.evaluate(
            input: PromptWriteGateInput(
                toolName: "Write",
                path: root.appendingPathComponent(".cursor/hooks.json").path,
                content: "{}"
            ),
            classifier: classifier
        )

        XCTAssertTrue(
            PromptWriteGateRenderer.render(decision: decision, adapter: .cursor)
                .stdout.contains(#""permission":"deny""#)
        )
        XCTAssertTrue(
            PromptWriteGateRenderer.render(decision: decision, adapter: .claude)
                .stdout.contains(#""permissionDecision":"deny""#)
        )
    }
}
