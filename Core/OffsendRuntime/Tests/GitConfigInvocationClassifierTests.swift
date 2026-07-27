import XCTest
@testable import OffsendRuntime

final class GitConfigInvocationClassifierTests: XCTestCase {
    func testDetectsExecutionSensitiveConfigWrites() {
        let cases: [(String, String)] = [
            ("git config core.hooksPath .githooks", "core.hookspath"),
            ("git config --global alias.deploy '!sh deploy.sh'", "alias.deploy"),
            ("git config --add credential.helper '!credential-command'", "credential.helper"),
            ("git config filter.assets.process ./processor", "filter.assets.process"),
            ("git config diff.custom.command ./diff-driver", "diff.custom.command"),
            ("git config merge.custom.driver './merge %O %A %B'", "merge.custom.driver"),
            ("git config includeIf.gitdir:~/work/.path ../agent.conf", "includeif.gitdir:~/work/.path"),
            ("git config pager.status 'sh -c payload'", "pager.status"),
            ("git config submodule.lib.update '!command'", "submodule.lib.update"),
        ]

        for (command, key) in cases {
            XCTAssertEqual(
                GitConfigInvocationClassifier.classify(command: command)?.key,
                key,
                command
            )
        }
    }

    func testDetectsMutationFormsAndGitGlobalOptions() {
        XCTAssertNotNil(
            GitConfigInvocationClassifier.classify(
                command: "git -C repo config set --local core.hooksPath .hooks"
            )
        )
        XCTAssertNotNil(
            GitConfigInvocationClassifier.classify(
                command: "/usr/bin/git config --unset-all credential.helper"
            )
        )
        XCTAssertNotNil(
            GitConfigInvocationClassifier.classify(command: "git config remove-section alias")
        )
        XCTAssertNotNil(
            GitConfigInvocationClassifier.classify(
                command: "env LC_ALL=C git config --rename-section alias shortcuts"
            )
        )
        XCTAssertNotNil(
            GitConfigInvocationClassifier.classify(command: "git config --global --edit")
        )
    }

    func testDetectsPerInvocationConfigOverrides() {
        XCTAssertEqual(
            GitConfigInvocationClassifier.classify(
                command: "git -c core.hooksPath=.agent-hooks commit"
            )?.operation,
            "invocation override"
        )
        XCTAssertNotNil(
            GitConfigInvocationClassifier.classify(
                command: "git -calias.run=!sh run"
            )
        )
        XCTAssertEqual(
            GitConfigInvocationClassifier.classify(
                command: "git --config-env=core.sshCommand=COMMAND_ENV fetch"
            )?.operation,
            "environment override"
        )
        XCTAssertNotNil(
            GitConfigInvocationClassifier.classify(
                command: "git --exec-path=.agent-bin custom-command"
            )
        )
    }

    func testAllowsReadsAndOrdinaryWrites() {
        let commands = [
            "git config core.hooksPath",
            "git config --get alias.deploy",
            "git config get credential.helper",
            "git config --list --show-origin",
            "git config user.name 'Offsend Bot'",
            "git config --local core.autocrlf input",
            "git -c color.ui=false status",
            "git status",
        ]

        for command in commands {
            XCTAssertNil(
                GitConfigInvocationClassifier.classify(command: command),
                command
            )
        }
    }

    func testDetectsAdditionalExecutionSensitiveKeys() {
        for key in [
            "core.pager",
            "core.askpass",
            "core.alternateRefsCommand",
            "init.templateDir",
            "uploadpack.packObjectsHook",
            "difftool.evil.cmd",
            "mergetool.evil.cmd",
            "guitool.evil.cmd",
            "diff.evil.textconv",
            "trailer.sign.command",
            "protocol.ext.allow",
            "remote.origin.uploadpack",
            "browser.evil.cmd",
        ] {
            XCTAssertNotNil(
                GitConfigInvocationClassifier.classify(command: "git config \(key) payload"),
                key
            )
        }
    }

    func testFindsInvocationThroughShellAndLauncherWrappers() {
        for command in [
            #"bash -c "git config core.hooksPath .evil""#,
            #"sh -c 'git config core.hooksPath .evil'"#,
            "timeout 5 git config core.hooksPath .evil",
            "xargs -I{} git config core.hooksPath .evil",
            #"timeout 5 bash -lc 'git config core.hooksPath .evil'"#,
        ] {
            XCTAssertNotNil(GitConfigInvocationClassifier.classify(command: command), command)
        }
    }

    func testFindsInvocationInsideStaticShellChainButNotQuotedText() {
        XCTAssertNotNil(
            GitConfigInvocationClassifier.classify(
                command: "echo ready && /opt/homebrew/bin/git config core.editor evil"
            )
        )
        XCTAssertNil(
            GitConfigInvocationClassifier.classify(
                command: #"printf '%s' "git config core.hooksPath .hooks""#
            )
        )
        XCTAssertNil(
            GitConfigInvocationClassifier.classify(
                command: "echo git config core.hooksPath .hooks"
            )
        )
        XCTAssertNotNil(
            GitConfigInvocationClassifier.classify(
                command: "/usr/bin/env LC_ALL=C git config core.hooksPath .hooks"
            )
        )
        XCTAssertNotNil(
            GitConfigInvocationClassifier.classify(
                command: "env -u HOME git config core.hooksPath .hooks"
            )
        )
    }
}
