import XCTest
@testable import OffsendRuntime

final class PromptShellGateTests: XCTestCase {
    func testAllowsHarmlessCommand() {
        let decision = PromptShellGate.evaluate(command: "swift build --product offsend")
        XCTAssertTrue(decision.allowed)
        XCTAssertTrue(decision.suspiciousPaths.isEmpty)
    }

    func testFlagsEnvFileRead() {
        let decision = PromptShellGate.evaluate(command: "cat .env")
        XCTAssertFalse(decision.allowed)
        XCTAssertTrue(decision.deny) // default context.shell.mode is deny
        XCTAssertEqual(decision.suspiciousPaths, [".env"])
        XCTAssertTrue(decision.reason.contains(".env"))
    }

    func testSensitivePathModeAskVsDeny() {
        let ask = PromptShellGate.evaluate(
            command: "cat .env",
            shellConfig: OffsendProjectShellConfig(mode: "ask")
        )
        XCTAssertFalse(ask.allowed)
        XCTAssertFalse(ask.deny)
        XCTAssertTrue(
            PromptShellGateRenderer.render(decision: ask, adapter: .cursor)
                .stdout.contains(#""permission":"ask""#)
        )

        let deny = PromptShellGate.evaluate(
            command: "cat cert.pem",
            shellConfig: OffsendProjectShellConfig(mode: "deny")
        )
        XCTAssertTrue(deny.deny)
        XCTAssertTrue(
            PromptShellGateRenderer.render(decision: deny, adapter: .cursor)
                .stdout.contains(#""permission":"deny""#)
        )
    }

    func testSeesSensitivePathsInInterpreterScriptsAndSubstitutions() {
        for command in [
            #"python3 -c "open('cert.pem')""#,
            #"python3 -copen('cert.pem')"#,
            #"node -e "require('fs').readFileSync('.env')""#,
            #"ruby -e "File.read('secrets/prod.key')""#,
            #"cat $(echo cert.pem)"#,
            #"cat $(printf '%s' .env)"#,
            "f=cert.pem; cat $f",
        ] {
            let decision = PromptShellGate.evaluate(command: command)
            XCTAssertFalse(decision.allowed, command)
            XCTAssertTrue(decision.deny, command)
        }
    }

    func testSeesSensitivePathsReconstructedFromStringConcatenation() {
        for command in [
            #"python3 -c 'from pathlib import Path; Path("c"+"ert"+".p"+"em").read_text()'"#,
            #"python3 -c 'open("c"+"ert"+".pem")'"#,
            #"python3 -c "open('s'+'ecrets'+'/credentials.json')""#,
            #"node -e 'require("fs").readFileSync("."+"env")'"#,
        ] {
            let decision = PromptShellGate.evaluate(command: command)
            XCTAssertFalse(decision.allowed, command)
            XCTAssertTrue(decision.deny, command)
        }

        // Benign concat must not trip the gate.
        let allow = PromptShellGate.evaluate(
            command: #"python3 -c 'print("hel"+"lo"+"world")'"#
        )
        XCTAssertTrue(allow.allowed)
    }

    func testStringConcatenationOnlyNormalizesInterpreterPayloads() {
        let dataOnly = PromptShellGate.evaluate(
            command: #"printf '%s' '"se"+"crets.json"'"#
        )
        XCTAssertTrue(dataOnly.allowed)
    }

    func testIgnorePatternsProtectReconstructedDirectories() {
        let root = URL(fileURLWithPath: "/tmp/offsend-shell-root", isDirectory: true)
        for command in [
            #"python3 -c 'from pathlib import Path; list(Path("s"+"ecrets").iterdir())'"#,
            #"python3 -c 'from pathlib import Path; list(Path("f"+"ixtures").iterdir())'"#,
        ] {
            let decision = PromptShellGate.evaluate(
                command: command,
                cwd: root.path,
                protectedPatterns: ["secrets/", "fixtures/"],
                projectRoot: root
            )
            XCTAssertFalse(decision.allowed, command)
            XCTAssertTrue(decision.deny, command)
        }
    }

    func testJSONEvaluationUsesDefaultCWDForProtectedPatterns() throws {
        let root = URL(fileURLWithPath: "/tmp/offsend-shell-root", isDirectory: true)
        let json = #"{"command":"python3 -c 'from pathlib import Path; list(Path(\"f\"+\"ixtures\").iterdir())'"}"#
        let decision = try PromptShellGate.evaluate(
            json: json,
            adapter: .cursor,
            protectedPatterns: ["fixtures/"],
            projectRoot: root,
            defaultCWD: root.path
        )
        XCTAssertFalse(decision.allowed)
        XCTAssertTrue(decision.deny)
    }

    func testInvalidInputDecisionDenies() {
        let decision = PromptShellGate.invalidInputDecision()
        XCTAssertTrue(decision.deny)
        XCTAssertTrue(
            PromptShellGateRenderer.render(decision: decision, adapter: .cursor)
                .stdout.contains(#""permission":"deny""#)
        )
    }

    func testFlagsAdditionalCredentialPaths() {
        XCTAssertFalse(PromptShellGate.evaluate(command: "cat config/master.key").allowed)
        XCTAssertFalse(PromptShellGate.evaluate(command: "less _netrc").allowed)
        XCTAssertFalse(PromptShellGate.evaluate(command: "cp secring.gpg /tmp/").allowed)
        XCTAssertFalse(PromptShellGate.evaluate(command: "cat .git-credentials").allowed)
    }

    func testFlagsSSHKeyCopy() {
        let decision = PromptShellGate.evaluate(command: "cp ~/.ssh/id_rsa /tmp/key")
        XCTAssertFalse(decision.allowed)
        XCTAssertEqual(decision.suspiciousPaths, ["id_rsa"])
    }

    func testFlagsQuotedAndAssignedPaths() {
        XCTAssertFalse(PromptShellGate.evaluate(command: "less \"./server.pem\"").allowed)
        XCTAssertFalse(PromptShellGate.evaluate(command: "deploy --key-file=secrets/prod.key").allowed)
        XCTAssertFalse(PromptShellGate.evaluate(command: "KUBECONFIG=~/.kube/config kubectl get pods").allowed)
    }

    func testIgnoresFlagsAndDeduplicates() {
        let decision = PromptShellGate.evaluate(command: "cat .env .env; rm -rf build")
        XCTAssertFalse(decision.allowed)
        XCTAssertEqual(decision.suspiciousPaths, [".env"])

        XCTAssertTrue(PromptShellGate.evaluate(command: "ls -la --color=auto src").allowed)
    }

    func testDeniesOffsendUnsealByDefault() {
        let direct = PromptShellGate.evaluate(command: "offsend unseal --key-name work < sealed.txt")
        XCTAssertFalse(direct.allowed)
        XCTAssertTrue(direct.deny)
        XCTAssertEqual(direct.suspiciousPaths, ["offsend unseal"])
        XCTAssertTrue(direct.reason.contains("unseal"))

        let viaPath = PromptShellGate.evaluate(command: "/usr/local/bin/offsend unseal file.txt")
        XCTAssertFalse(viaPath.allowed)

        let piped = PromptShellGate.evaluate(command: "cat sealed.txt | offsend unseal")
        XCTAssertFalse(piped.allowed)

        let ask = PromptShellGate.evaluate(
            command: "offsend unseal sealed.txt",
            shellConfig: OffsendProjectShellConfig(mode: "ask")
        )
        XCTAssertFalse(ask.deny)
    }

    func testDoesNotFlagUnrelatedUnsealMentions() {
        // `unseal` without the offsend binary, and offsend without unseal.
        XCTAssertTrue(PromptShellGate.evaluate(command: "vault operator unseal").allowed)
        XCTAssertTrue(PromptShellGate.evaluate(command: "offsend check README.md").allowed)
        XCTAssertTrue(PromptShellGate.evaluate(command: "offsend seal notes.txt").allowed)
    }

    func testDeniesPolicyTrustAndForgetInAgentShell() {
        for command in [
            "offsend policy trust",
            "/opt/homebrew/bin/offsend policy forget --path .",
        ] {
            let decision = PromptShellGate.evaluate(command: command)
            XCTAssertFalse(decision.allowed)
            XCTAssertTrue(decision.deny)

            let cursor = PromptShellGateRenderer.render(decision: decision, adapter: .cursor)
            XCTAssertTrue(cursor.stdout.contains("\"permission\":\"deny\""))

            let claude = PromptShellGateRenderer.render(decision: decision, adapter: .claude)
            XCTAssertTrue(claude.stdout.contains("\"permissionDecision\":\"deny\""))
        }
        XCTAssertTrue(PromptShellGate.evaluate(command: "offsend policy status").allowed)
    }

    func testDeniesDirectWriteToExecutableWorkspaceConfig() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent(".git/hooks", isDirectory: true),
            withIntermediateDirectories: true
        )
        let classifier = ExecutableArtifactClassifier(
            projectRoot: root,
            gitResolver: GitRepositoryResolver(gitExecutable: "/nonexistent/git")
        )

        let decision = PromptShellGate.evaluate(
            command: "printf malicious > .cursor/hooks.json",
            cwd: root.path,
            classifier: classifier
        )

        XCTAssertTrue(decision.deny)
        XCTAssertFalse(decision.allowed)
        XCTAssertTrue(decision.reason.contains("executable workspace configuration"))

        let startup = PromptShellGate.evaluate(
            command: "printf malicious >> .envrc",
            cwd: root.path,
            classifier: classifier
        )
        XCTAssertTrue(startup.deny)
        XCTAssertFalse(startup.allowed)
    }

    func testDeniesPolicyAndTrustStoreMutationsViaShell() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let store = root.appendingPathComponent("trust-store", isDirectory: true)
        let classifier = ExecutableArtifactClassifier(
            projectRoot: root,
            gitResolver: GitRepositoryResolver(gitExecutable: "/nonexistent/git"),
            trustStoreRoot: store
        )

        for command in [
            "printf 'check:\\n  exclude: [\"**\"]' > .offsend.yml",
            "rm -rf \(store.path)/policy",
        ] {
            let decision = PromptShellGate.evaluate(
                command: command,
                cwd: root.path,
                classifier: classifier
            )
            XCTAssertTrue(decision.deny, command)
        }
    }

    func testContentConditionalEditorSettingsHonorShellMode() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let classifier = ExecutableArtifactClassifier(
            projectRoot: root,
            gitResolver: GitRepositoryResolver(gitExecutable: "/nonexistent/git")
        )

        let denied = PromptShellGate.evaluate(
            command: "printf '{}' > .vscode/settings.json",
            cwd: root.path,
            classifier: classifier
        )
        XCTAssertTrue(denied.deny)
        XCTAssertFalse(denied.allowed)
        XCTAssertTrue(denied.reason.contains("settings.json"))

        let ask = PromptShellGate.evaluate(
            command: "printf '{}' > .vscode/settings.json",
            cwd: root.path,
            classifier: classifier,
            shellConfig: OffsendProjectShellConfig(mode: "ask")
        )
        XCTAssertFalse(ask.deny)
        XCTAssertFalse(ask.allowed)
    }

    func testDeniesExecutionSensitiveGitConfigMutations() {
        for command in [
            "git config core.hooksPath .agent-hooks",
            "git config --global alias.deploy '!sh payload.sh'",
            "git -c core.sshCommand=./wrapper fetch",
            "git --config-env=credential.helper=HELPER_ENV fetch",
        ] {
            let decision = PromptShellGate.evaluate(command: command)
            XCTAssertFalse(decision.allowed, command)
            XCTAssertTrue(decision.deny, command)
            XCTAssertTrue(decision.reason.contains("execution-sensitive"), command)
            XCTAssertTrue(
                PromptShellGateRenderer.render(decision: decision, adapter: .cursor)
                    .stdout.contains(#""permission":"deny""#),
                command
            )
        }
    }

    func testAllowsGitConfigReadsAndOrdinarySettings() {
        for command in [
            "git config --get core.hooksPath",
            "git config user.name 'Offsend Bot'",
            "git -c color.ui=false status",
        ] {
            XCTAssertTrue(PromptShellGate.evaluate(command: command).allowed, command)
        }
    }

    func testDeniesPrivilegedDaemonExecutionAndSocketAccess() {
        for command in [
            "docker run --rm alpine id",
            "podman exec app sh",
            "docker compose up -d",
            "curl --unix-socket /var/run/docker.sock http://localhost/version",
        ] {
            let decision = PromptShellGate.evaluate(command: command)
            XCTAssertFalse(decision.allowed, command)
            XCTAssertTrue(decision.deny, command)
            XCTAssertTrue(decision.reason.contains("outside the agent sandbox"), command)
        }
    }

    func testLowerRiskDaemonMutationHonorsShellMode() {
        let denied = PromptShellGate.evaluate(command: "docker build .")
        XCTAssertFalse(denied.allowed)
        XCTAssertTrue(denied.deny)

        let ask = PromptShellGate.evaluate(
            command: "docker build .",
            shellConfig: OffsendProjectShellConfig(mode: "ask")
        )
        XCTAssertFalse(ask.allowed)
        XCTAssertFalse(ask.deny)
        XCTAssertTrue(
            PromptShellGateRenderer.render(decision: ask, adapter: .cursor)
                .stdout.contains(#""permission":"ask""#)
        )

        XCTAssertTrue(PromptShellGate.evaluate(command: "docker ps").allowed)
        XCTAssertTrue(PromptShellGate.evaluate(command: "docker image inspect alpine").allowed)
    }

    func testDeniesExecutionSensitiveEnvironmentPoisoning() {
        for command in [
            "PATH=./bin:/usr/bin make",
            "DYLD_INSERT_LIBRARIES=./payload.dylib app",
            "LD_PRELOAD=/tmp/payload.so app",
            "GIT_SSH_COMMAND=./wrapper git fetch",
            "BASH_ENV=./bootstrap.sh bash",
        ] {
            let decision = PromptShellGate.evaluate(command: command, cwd: "/workspace")
            XCTAssertFalse(decision.allowed, command)
            XCTAssertTrue(decision.deny, command)
            XCTAssertTrue(decision.reason.contains("environment"), command)
        }
    }

    func testSystemPathOverrideHonorsShellMode() {
        let denied = PromptShellGate.evaluate(
            command: "PATH=/opt/homebrew/bin:/usr/bin:$PATH make",
            cwd: "/workspace"
        )
        XCTAssertFalse(denied.allowed)
        XCTAssertTrue(denied.deny)

        let ask = PromptShellGate.evaluate(
            command: "PATH=/opt/homebrew/bin:/usr/bin:$PATH make",
            cwd: "/workspace",
            shellConfig: OffsendProjectShellConfig(mode: "ask")
        )
        XCTAssertFalse(ask.allowed)
        XCTAssertFalse(ask.deny)

        XCTAssertTrue(
            PromptShellGate.evaluate(command: "GIT_AUTHOR_NAME=Bot git status").allowed
        )
    }

    func testExtractCommandCursorAndClaude() throws {
        let cursorJSON = #"{"command":"cat .env","cwd":"/repo"}"#
        let cursor = try PromptShellGate.evaluate(json: cursorJSON, adapter: .cursor)
        XCTAssertEqual(cursor.command, "cat .env")

        let claudeJSON = #"{"tool_input":{"command":"cat .env"}}"#
        let claude = try PromptShellGate.evaluate(json: claudeJSON, adapter: .claude)
        XCTAssertEqual(claude.command, "cat .env")
    }

    func testInvalidJSONThrows() {
        XCTAssertThrowsError(try PromptShellGate.evaluate(json: "not json", adapter: .cursor))
        XCTAssertThrowsError(try PromptShellGate.evaluate(json: "{}", adapter: .cursor))
    }

    func testCursorRendererDeniesSensitiveFindingsByDefault() {
        let decision = PromptShellGate.evaluate(command: "cat .env")
        let output = PromptShellGateRenderer.render(decision: decision, adapter: .cursor)
        XCTAssertTrue(output.stdout.contains("\"permission\":\"deny\""))
        XCTAssertTrue(output.stdout.contains("user_message"))
        XCTAssertEqual(output.exitCode, 0)

        let allowed = PromptShellGateRenderer.render(
            decision: PromptShellGate.evaluate(command: "ls"),
            adapter: .cursor
        )
        XCTAssertTrue(allowed.stdout.contains("\"permission\":\"allow\""))
    }

    func testClaudeRendererDeniesSensitiveFindingsByDefault() {
        let decision = PromptShellGate.evaluate(command: "cat .env")
        let output = PromptShellGateRenderer.render(decision: decision, adapter: .claude)
        XCTAssertTrue(output.stdout.contains("\"permissionDecision\":\"deny\""))
        XCTAssertEqual(output.exitCode, 0)

        let allowed = PromptShellGateRenderer.render(
            decision: PromptShellGate.evaluate(command: "ls"),
            adapter: .claude
        )
        XCTAssertEqual(allowed.stdout, "{}")
    }

    func testSeesThroughShellAndLauncherWrappers() {
        for command in [
            #"bash -c "git config core.hooksPath .evil""#,
            #"sh -c 'git config core.hooksPath .evil'"#,
            #"bash -lc 'git config core.hooksPath .evil'"#,
            "timeout 5 git config core.hooksPath .evil",
            "nice -n 10 git config core.hooksPath .evil",
            #"timeout 5 bash -c 'git config core.hooksPath .evil'"#,
        ] {
            let decision = PromptShellGate.evaluate(command: command)
            XCTAssertTrue(decision.deny, command)
            XCTAssertTrue(decision.reason.contains("core.hookspath"), command)
        }
    }

    func testSeesSensitivePathsThroughQuotingAndRedirection() {
        XCTAssertFalse(PromptShellGate.evaluate(command: #"cat '.en'v"#).allowed)
        XCTAssertFalse(PromptShellGate.evaluate(command: #"cat ".en"v"#).allowed)
        XCTAssertFalse(PromptShellGate.evaluate(command: #"printf x >.env"#).allowed)
        XCTAssertFalse(PromptShellGate.evaluate(command: #"printf x 2>>.env"#).allowed)
        XCTAssertFalse(PromptShellGate.evaluate(command: #"bash -c "cat .env""#).allowed)
        // A digit-prefixed name is not a redirection.
        XCTAssertTrue(PromptShellGate.evaluate(command: "cat 2024-notes.txt").allowed)
    }

    func testReportsEveryFindingRatherThanTheFirst() {
        let decision = PromptShellGate.evaluate(
            command: "git config core.hooksPath .evil && cat .env"
        )
        XCTAssertTrue(decision.deny)
        XCTAssertEqual(decision.suspiciousPaths, ["git config core.hookspath", ".env"])
        XCTAssertTrue(decision.reason.contains("core.hookspath"))
        XCTAssertTrue(decision.reason.contains(".env"))
    }

    func testDenialsLeadTheReportedReason() {
        let decision = PromptShellGate.evaluate(command: "cat .env && git config core.editor evil")
        XCTAssertTrue(decision.deny)
        XCTAssertEqual(decision.suspiciousPaths.first, "git config core.editor")
    }

    func testFlagsSymlinkToSensitiveTargetViaCwd() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("offsend-shell-gate-symlink-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let env = root.appendingPathComponent(".env")
        let link = root.appendingPathComponent("notes.txt")
        try "SECRET=1\n".write(to: env, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: env)

        let decision = PromptShellGate.evaluate(command: "cat notes.txt", cwd: root.path)
        XCTAssertFalse(decision.allowed)
        XCTAssertEqual(decision.suspiciousPaths, [".env"])

        let json = #"{"command":"cat notes.txt","cwd":"\#(root.path)"}"#
        let fromJSON = try PromptShellGate.evaluate(json: json, adapter: .cursor)
        XCTAssertFalse(fromJSON.allowed)
        XCTAssertEqual(fromJSON.suspiciousPaths, [".env"])
    }
}
