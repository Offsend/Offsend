import XCTest
@testable import OffsendRuntime

final class ExecutableArtifactClassifierTests: XCTestCase {
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

    func testDeniesEditorHookAndTaskConfigs() {
        let paths: [(String, ExecutableArtifactKind)] = [
            (".cursor/hooks.json", .editorHookConfig),
            (".claude/settings.json", .editorHookConfig),
            (".claude/settings.local.json", .editorHookConfig),
            (".windsurf/hooks.json", .editorHookConfig),
            (".codex/hooks.json", .editorHookConfig),
            (".vscode/tasks.json", .editorTaskConfig),
        ]

        for (path, kind) in paths {
            let match = classifier.classify(path: path, cwd: root.path)
            XCTAssertEqual(match?.kind, kind, path)
            XCTAssertEqual(match?.enforcement, .deny, path)
        }
    }

    func testDeniesGitDirectoryConfigAndHooks() {
        XCTAssertEqual(
            classifier.classify(path: root.appendingPathComponent(".git").path)?.kind,
            .gitDirectoryPointer
        )
        XCTAssertEqual(
            classifier.classify(path: root.appendingPathComponent(".git/config").path)?.kind,
            .gitConfig
        )
        XCTAssertEqual(
            classifier.classify(path: root.appendingPathComponent(".git/hooks/pre-commit").path)?.kind,
            .gitHook
        )
    }

    func testVirtualEnvironmentInterpreterIsObserveOnly() {
        let match = classifier.classify(path: ".venv/bin/python3.13", cwd: root.path)

        XCTAssertEqual(match?.kind, .virtualEnvironmentInterpreter)
        XCTAssertEqual(match?.enforcement, .observe)
    }

    func testDeniesShellStartupAndDirenvConfigs() {
        for path in [
            ".zshrc",
            ".bash_profile",
            ".envrc",
            ".config/fish/config.fish",
            ".config/direnv/direnvrc",
        ] {
            let match = classifier.classify(path: path, cwd: root.path)
            XCTAssertEqual(match?.kind, .shellStartupConfig, path)
            XCTAssertEqual(match?.enforcement, .deny, path)
        }
    }

    func testAllowsOrdinarySourceAndVenvLibraryFiles() {
        XCTAssertNil(classifier.classify(path: "Sources/App.swift", cwd: root.path))
        XCTAssertNil(classifier.classify(path: ".venv/lib/python/site.py", cwd: root.path))
    }

    func testDeniesOffsendPolicyAndTrustStore() throws {
        let store = root.appendingPathComponent("trust-store", isDirectory: true)
        let classifier = ExecutableArtifactClassifier(
            projectRoot: root,
            gitResolver: GitRepositoryResolver(gitExecutable: "/nonexistent/git"),
            trustStoreRoot: store
        )

        let policy = classifier.classify(path: ".offsend.yml", cwd: root.path)
        XCTAssertEqual(policy?.kind, .offsendPolicy)
        XCTAssertEqual(policy?.enforcement, .deny)

        let snapshot = classifier.classify(path: store.appendingPathComponent("policy/abc.json").path)
        XCTAssertEqual(snapshot?.kind, .offsendTrustStore)
        XCTAssertEqual(snapshot?.enforcement, .deny)

        XCTAssertNil(classifier.classify(path: ".offsend.yml.example", cwd: root.path))
    }

    func testMatchesRegardlessOfCaseAndUnicodeForm() {
        XCTAssertEqual(
            classifier.classify(path: ".CURSOR/Hooks.JSON", cwd: root.path)?.kind,
            .editorHookConfig
        )
        // NFD form of `.café/…` is not a trust surface, but the same rule path
        // must not break on decomposed input for one that is.
        let decomposed = ".cursor/hooks.json".decomposedStringWithCanonicalMapping
        XCTAssertEqual(classifier.classify(path: decomposed, cwd: root.path)?.kind, .editorHookConfig)
    }

    func testDeniesGitSurfacesAtAnyDepth() {
        for path in [
            "vendor/dependency/.git/config",
            "vendor/dependency/.git/hooks/pre-commit",
            ".git/modules/sub/hooks/post-checkout",
            ".git/info/exclude",
            "nested/.git",
        ] {
            XCTAssertEqual(classifier.classify(path: path, cwd: root.path)?.enforcement, .deny, path)
        }
        XCTAssertEqual(classifier.classify(path: ".gitconfig", cwd: root.path)?.kind, .gitConfig)
        XCTAssertEqual(
            classifier.classify(path: ".config/git/config", cwd: root.path)?.kind,
            .gitConfig
        )
    }

    func testDeniesEditorConfigInSubdirectory() {
        XCTAssertEqual(
            classifier.classify(path: "packages/api/.vscode/launch.json", cwd: root.path)?.kind,
            .editorTaskConfig
        )
        XCTAssertEqual(
            classifier.classify(path: "packages/api/.cursor/hooks.json", cwd: root.path)?.kind,
            .editorHookConfig
        )
    }

    func testEditorSettingsAreContentConditional() {
        for path in ["/.vscode/settings.json", "/team.code-workspace"] {
            let match = classifier.classify(path: root.path + path)
            XCTAssertEqual(match?.kind, .editorSettings, path)
            XCTAssertEqual(match?.enforcement, .denyWhenContentExecutable, path)
        }
    }

    func testDeniesPythonStartupHooksAndSSHAndLaunchAgents() {
        let cases: [(String, ExecutableArtifactKind)] = [
            (".venv/lib/python3.13/site-packages/evil.pth", .pythonStartupHook),
            (".venv/lib/python3.13/site-packages/sitecustomize.py", .pythonStartupHook),
            ("home/.ssh/config", .sshConfig),
            ("home/.ssh/authorized_keys", .sshConfig),
            ("Library/LaunchAgents/com.evil.plist", .launchAgent),
        ]

        for (path, kind) in cases {
            let match = classifier.classify(path: path, cwd: root.path)
            XCTAssertEqual(match?.kind, kind, path)
            XCTAssertEqual(match?.enforcement, .deny, path)
        }
    }

    func testClassifiesUnderSymlinkedProjectRoot() throws {
        let real = root.appendingPathComponent("real", isDirectory: true)
        try FileManager.default.createDirectory(
            at: real.appendingPathComponent(".cursor", isDirectory: true),
            withIntermediateDirectories: true
        )
        let link = root.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        let classifier = ExecutableArtifactClassifier(
            projectRoot: link,
            gitResolver: GitRepositoryResolver(gitExecutable: "/nonexistent/git")
        )

        // The editor may report either spelling of the same file.
        XCTAssertEqual(
            classifier.classify(path: link.appendingPathComponent(".cursor/hooks.json").path)?.kind,
            .editorHookConfig
        )
        XCTAssertEqual(
            classifier.classify(path: real.appendingPathComponent(".cursor/hooks.json").path)?.kind,
            .editorHookConfig
        )
    }

    func testClassifiesSymlinkResolvedTarget() throws {
        let cursorDirectory = root.appendingPathComponent(".cursor", isDirectory: true)
        try FileManager.default.createDirectory(at: cursorDirectory, withIntermediateDirectories: true)
        let target = cursorDirectory.appendingPathComponent("hooks.json")
        try "{}".write(to: target, atomically: true, encoding: .utf8)
        let alias = root.appendingPathComponent("safe.json")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: target)

        XCTAssertEqual(classifier.classify(path: alias.path)?.kind, .editorHookConfig)
    }
}
