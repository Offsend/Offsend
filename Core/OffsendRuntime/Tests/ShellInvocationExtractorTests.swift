import XCTest
@testable import OffsendRuntime

final class ShellInvocationExtractorTests: XCTestCase {
    private func executables(_ command: String) -> [String] {
        ShellInvocationExtractor.invocations(in: command).compactMap(\.executableName)
    }

    func testLexerKeepsQuotedSegmentsTogether() {
        XCTAssertEqual(
            ShellInvocationExtractor.tokens(#"cat '.git'/config"#),
            ["cat", ".git/config"]
        )
        XCTAssertEqual(
            ShellInvocationExtractor.tokens(#"cp "my file.txt" /tmp"#),
            ["cp", "my file.txt", "/tmp"]
        )
        XCTAssertEqual(
            ShellInvocationExtractor.tokens(#"echo a && echo b | wc -l"#),
            ["echo", "a", "&&", "echo", "b", "|", "wc", "-l"]
        )
    }

    func testPeelsLauncherWrappers() {
        XCTAssertEqual(executables("timeout 5 git status"), ["git"])
        XCTAssertEqual(executables("timeout --signal=KILL 5s git status"), ["git"])
        XCTAssertEqual(executables("nice -n 10 git status"), ["git"])
        XCTAssertEqual(executables("stdbuf -oL git status"), ["git"])
        XCTAssertEqual(executables("nohup setsid git status"), ["git"])
        XCTAssertEqual(executables("xargs -I{} git status"), ["git"])
        XCTAssertEqual(executables("sudo -u root env FOO=1 git status"), ["git"])
    }

    func testTimeoutDurationIsNotMistakenForTheCommand() {
        let invocation = ShellInvocationExtractor.invocations(in: "timeout 5 git status").first
        XCTAssertEqual(invocation?.arguments, ["git", "status"])
    }

    func testDescendsIntoInlineShellScripts() {
        XCTAssertEqual(executables(#"bash -c "git status""#), ["bash", "git"])
        XCTAssertEqual(executables(#"bash -lc 'git status'"#), ["bash", "git"])
        XCTAssertEqual(executables(#"sh -c 'git status'"#), ["sh", "git"])
        XCTAssertEqual(executables(#"timeout 5 bash -c 'git status'"#), ["bash", "git"])
        XCTAssertEqual(
            executables(#"env -S "git status""#),
            ["git"]
        )
    }

    func testStopsDescendingAtDepthLimit() {
        var command = "git status"
        for _ in 0...(ShellInvocationExtractor.maxDepth + 2) {
            command = "bash -c '\(command)'"
        }
        // The lexer strips one quoting level per pass, so deep nesting eventually
        // stops producing new invocations instead of recursing without bound.
        XCTAssertLessThanOrEqual(
            ShellInvocationExtractor.invocations(in: command).count,
            ShellInvocationExtractor.maxDepth + 2
        )
    }

    func testShellScriptFileIsNotTreatedAsInlineCommand() {
        XCTAssertEqual(executables("bash deploy.sh git"), ["bash"])
    }

    func testCommandLookupIsNotAnInvocation() {
        XCTAssertEqual(executables("command -v git"), [])
    }

    func testAttachesAssignmentsToTheInvocation() {
        let invocation = ShellInvocationExtractor.invocations(in: "FOO=1 BAR=2 git status").first
        XCTAssertEqual(invocation?.assignments.map(\.name), ["FOO", "BAR"])
        XCTAssertEqual(invocation?.arguments, ["git", "status"])

        let viaEnv = ShellInvocationExtractor.invocations(in: "env FOO=1 git status").first
        XCTAssertEqual(viaEnv?.assignments.map(\.name), ["FOO"])
        XCTAssertEqual(viaEnv?.arguments, ["git", "status"])
    }

    func testAssignmentOnlySegmentStillReportsItsEnvironment() {
        let invocation = ShellInvocationExtractor.invocations(in: "export FOO=1").first
        XCTAssertEqual(invocation?.arguments, ["export", "FOO=1"])
    }

    func testAllTokensIncludesNestedScriptTokens() {
        let tokens = ShellInvocationExtractor.allTokens(in: #"bash -c "cat .env""#)
        XCTAssertTrue(tokens.contains(".env"))
        XCTAssertFalse(tokens.contains("&&"))
    }

    func testAllTokensIncludesInterpreterInlineScripts() {
        let python = ShellInvocationExtractor.allTokens(in: #"python3 -c "open('cert.pem')""#)
        XCTAssertTrue(python.contains("open('cert.pem')") || python.contains("cert.pem"))

        let node = ShellInvocationExtractor.allTokens(in: #"node -e "require('fs').readFileSync('.env')""#)
        XCTAssertTrue(node.contains(".env") || node.contains("require('fs').readFileSync('.env')"))

        let ruby = ShellInvocationExtractor.allTokens(in: #"ruby -e "File.read('id_rsa')""#)
        XCTAssertTrue(ruby.contains("id_rsa") || ruby.contains("File.read('id_rsa')"))
    }

    func testCommandSubstitutionBodiesAreCollected() {
        XCTAssertEqual(
            ShellInvocationExtractor.commandSubstitutionBodies(in: #"cat $(echo cert.pem)"#),
            ["echo cert.pem"]
        )
        let tokens = ShellInvocationExtractor.allTokens(in: #"cat $(printf '%s' .env)"#)
        XCTAssertTrue(tokens.contains(".env") || tokens.contains("printf"))
    }
}
