import XCTest
@testable import OffsendRuntime

final class AIEditorHookInstallerTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("offsend-ai-hooks-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testInstallCursorMergesWithoutClobberingForeignHooks() throws {
        let configURL = root.appendingPathComponent(".cursor/hooks.json")
        try FileManager.default.createDirectory(
            at: configURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let existing: [String: Any] = [
            "version": 1,
            "hooks": [
                "beforeShellExecution": [
                    ["command": "./hooks/audit.sh"],
                ],
            ],
        ]
        let existingData = try JSONSerialization.data(withJSONObject: existing, options: [.prettyPrinted])
        try existingData.write(to: configURL)

        let installer = AIEditorHookInstaller()
        let result = try installer.install(
            target: .cursor,
            repositoryPath: root,
            cliExecutablePath: "/usr/local/bin/offsend",
            hookPolicy: .softBlock
        )

        XCTAssertTrue(result.command.contains(AIEditorHookInstaller.wrapperRelativePath))
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: result.wrapperPath))

        let data = try Data(contentsOf: configURL)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let hooks = try XCTUnwrap(object["hooks"] as? [String: Any])
        XCTAssertNotNil(hooks["beforeShellExecution"])
        let beforeSubmit = try XCTUnwrap(hooks["beforeSubmitPrompt"] as? [[String: Any]])
        XCTAssertEqual(beforeSubmit.count, 1)
        let command = try XCTUnwrap(beforeSubmit.first?["command"] as? String)
        XCTAssertTrue(command.contains(".offsend/hooks/check-prompt.sh"))
        XCTAssertTrue(command.contains("soft-block"))
        XCTAssertEqual(beforeSubmit.first?["failClosed"] as? Bool, false)
        XCTAssertTrue(installer.status(target: .cursor, repositoryPath: root).installed)
    }

    func testInstallClaudeMergesSettingsAndUninstall() throws {
        let settingsURL = root.appendingPathComponent(".claude/settings.json")
        try FileManager.default.createDirectory(
            at: settingsURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try #"{"permissions":{"allow":["Bash"]}}"#.write(to: settingsURL, atomically: true, encoding: .utf8)

        let installer = AIEditorHookInstaller()
        _ = try installer.install(
            target: .claude,
            repositoryPath: root,
            cliExecutablePath: "/opt/offsend",
            hookPolicy: .advise
        )
        let data = try Data(contentsOf: settingsURL)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNotNil(object["permissions"])
        let hooks = try XCTUnwrap(object["hooks"] as? [String: Any])
        XCTAssertNotNil(hooks["UserPromptSubmit"])

        try installer.uninstall(target: .claude, repositoryPath: root)
        let after = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: settingsURL)) as? [String: Any]
        )
        XCTAssertNotNil(after["permissions"])
        let afterHooks = after["hooks"] as? [String: Any] ?? [:]
        XCTAssertNil(afterHooks["UserPromptSubmit"])
        XCTAssertFalse(installer.status(target: .claude, repositoryPath: root).installed)
    }

    func testWrapperFailOpenAndNoNotify() throws {
        let installer = AIEditorHookInstaller()
        let result = try installer.install(
            target: .windsurf,
            repositoryPath: root,
            cliExecutablePath: "/usr/local/bin/offsend"
        )
        let script = try String(contentsOfFile: result.wrapperPath, encoding: .utf8)
        XCTAssertTrue(script.contains("--no-notify"))
        XCTAssertTrue(script.contains(AIEditorHookInstaller.managedMarker))
        XCTAssertTrue(script.contains("continue"))
        XCTAssertTrue(script.contains("windsurf) : ;;"))
        XCTAssertEqual(AIEditorHookInstaller.defaultHookPolicy(for: .windsurf), .softBlock)
    }

    func testWrapperPrefersInstallTimePathBeforePathLookup() throws {
        let installer = AIEditorHookInstaller()
        let result = try installer.install(
            target: .cursor,
            repositoryPath: root,
            cliExecutablePath: "/usr/local/bin/offsend"
        )
        let script = try String(contentsOfFile: result.wrapperPath, encoding: .utf8)
        XCTAssertTrue(script.contains("if [ -x \"${PREFERRED_BIN}\" ]; then"))
        XCTAssertTrue(script.contains("OFFSEND_BIN=\"${PREFERRED_BIN}\""))
        guard
            let preferredRange = script.range(of: "OFFSEND_BIN=\"${PREFERRED_BIN}\""),
            let pathLookupRange = script.range(of: "command -v offsend")
        else {
            return XCTFail("Expected pinned-path resolution before PATH lookup")
        }
        XCTAssertLessThan(preferredRange.lowerBound, pathLookupRange.lowerBound)
    }

    func testValidateWrapperAcceptsManagedScript() throws {
        let installer = AIEditorHookInstaller()
        let result = try installer.install(
            target: .cursor,
            repositoryPath: root,
            cliExecutablePath: "/usr/local/bin/offsend"
        )
        let validation = installer.validateWrapper(at: URL(fileURLWithPath: result.wrapperPath))
        XCTAssertEqual(validation, .ok)
        let script = try String(contentsOfFile: result.wrapperPath, encoding: .utf8)
        XCTAssertEqual(
            AIEditorHookInstaller.parseManagedVersion(in: script),
            AIEditorHookInstaller.managedVersion
        )
    }

    func testValidateWrapperDetectsTamperedScript() throws {
        let installer = AIEditorHookInstaller()
        let result = try installer.install(
            target: .cursor,
            repositoryPath: root,
            cliExecutablePath: "/usr/local/bin/offsend"
        )
        try "#!/bin/sh\necho pwned".write(
            to: URL(fileURLWithPath: result.wrapperPath),
            atomically: true,
            encoding: .utf8
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: result.wrapperPath
        )
        XCTAssertEqual(installer.validateWrapper(at: URL(fileURLWithPath: result.wrapperPath)), .missingManagedMarker)
        XCTAssertTrue(installer.status(target: .cursor, repositoryPath: root).broken)
    }

    func testValidateWrapperDetectsOutdatedVersion() throws {
        let wrapperURL = root.appendingPathComponent(AIEditorHookInstaller.wrapperRelativePath)
        try FileManager.default.createDirectory(
            at: wrapperURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let script = """
        #!/bin/sh
        # \(AIEditorHookInstaller.managedMarker) v0
        echo old
        """
        try script.write(to: wrapperURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: wrapperURL.path)
        let installer = AIEditorHookInstaller()
        XCTAssertEqual(installer.validateWrapper(at: wrapperURL), .outdatedVersion(found: 0))
    }

    func testInstallRefusesForeignWrapperWithoutForce() throws {
        let wrapperURL = root.appendingPathComponent(AIEditorHookInstaller.wrapperRelativePath)
        try FileManager.default.createDirectory(
            at: wrapperURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "#!/bin/sh\necho custom".write(to: wrapperURL, atomically: true, encoding: .utf8)

        XCTAssertThrowsError(
            try AIEditorHookInstaller().install(
                target: .cursor,
                repositoryPath: root,
                cliExecutablePath: "/usr/local/bin/offsend"
            )
        ) { error in
            guard case .wrapperAlreadyExists(let path) = error as? AIEditorHookInstallerError else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(path, wrapperURL.path)
        }
        XCTAssertEqual(try String(contentsOf: wrapperURL, encoding: .utf8), "#!/bin/sh\necho custom")
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(".cursor/hooks.json").path))
    }

    func testInstallForceReplacesForeignWrapper() throws {
        let wrapperURL = root.appendingPathComponent(AIEditorHookInstaller.wrapperRelativePath)
        try FileManager.default.createDirectory(
            at: wrapperURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "#!/bin/sh\necho custom".write(to: wrapperURL, atomically: true, encoding: .utf8)

        _ = try AIEditorHookInstaller().install(
            target: .cursor,
            repositoryPath: root,
            cliExecutablePath: "/usr/local/bin/offsend",
            force: true
        )

        XCTAssertTrue(try String(contentsOf: wrapperURL, encoding: .utf8).contains(AIEditorHookInstaller.managedMarker))
    }

    func testInstallPreflightsReadWrapperBeforeWritingPromptWrapper() throws {
        let readURL = root.appendingPathComponent(AIEditorHookInstaller.readWrapperRelativePath)
        try FileManager.default.createDirectory(
            at: readURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "#!/bin/sh\necho custom".write(to: readURL, atomically: true, encoding: .utf8)

        XCTAssertThrowsError(
            try AIEditorHookInstaller().install(
                target: .cursor,
                repositoryPath: root,
                cliExecutablePath: "/usr/local/bin/offsend",
                withReadGate: true
            )
        )
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: root.appendingPathComponent(AIEditorHookInstaller.wrapperRelativePath).path
            )
        )
    }

    func testInstallPreflightsInvalidConfigBeforeWritingWrapper() throws {
        let configURL = root.appendingPathComponent(".cursor/hooks.json")
        try FileManager.default.createDirectory(
            at: configURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "not-json".write(to: configURL, atomically: true, encoding: .utf8)

        XCTAssertThrowsError(
            try AIEditorHookInstaller().install(
                target: .cursor,
                repositoryPath: root,
                cliExecutablePath: "/usr/local/bin/offsend"
            )
        ) { error in
            guard case .invalidExistingConfig = error as? AIEditorHookInstallerError else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: root.appendingPathComponent(AIEditorHookInstaller.wrapperRelativePath).path
            )
        )
    }

    func testInstallRejectsMissingRepositoryDirectory() {
        let missing = root.appendingPathComponent("missing", isDirectory: true)

        XCTAssertThrowsError(
            try AIEditorHookInstaller().install(
                target: .cursor,
                repositoryPath: missing,
                cliExecutablePath: "/usr/local/bin/offsend"
            )
        ) { error in
            guard case .repositoryPathNotDirectory(let path) = error as? AIEditorHookInstallerError else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(path, missing.path)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: missing.path))
    }

    func testUninstallPreservesForeignWrapper() throws {
        let installer = AIEditorHookInstaller()
        let result = try installer.install(
            target: .cursor,
            repositoryPath: root,
            cliExecutablePath: "/usr/local/bin/offsend"
        )
        try "#!/bin/sh\necho custom".write(
            to: URL(fileURLWithPath: result.wrapperPath),
            atomically: true,
            encoding: .utf8
        )

        try installer.uninstall(target: .cursor, repositoryPath: root)

        XCTAssertTrue(FileManager.default.fileExists(atPath: result.wrapperPath))
    }

    func testManagedMarkerOutsideHeaderIsRejected() {
        let script = """
        #!/bin/sh
        echo start
        # \(AIEditorHookInstaller.managedMarker) v1
        """
        XCTAssertNil(AIEditorHookInstaller.parseManagedVersion(in: script))
    }

    func testDetectedTargetsAlwaysIncludeCursorAndClaude() throws {
        let home = root.appendingPathComponent("home", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        let targets = AIEditorHookTarget.detectedTargets(repositoryPath: root, homeDirectory: home)
        XCTAssertEqual(targets, [.cursor, .claude])
    }

    func testDetectedTargetsPickUpRepoLocalEditorDirectories() throws {
        let home = root.appendingPathComponent("home", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent(".windsurf"),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent(".codex"),
            withIntermediateDirectories: true
        )
        let targets = AIEditorHookTarget.detectedTargets(repositoryPath: root, homeDirectory: home)
        XCTAssertEqual(targets, [.cursor, .claude, .windsurf, .codex])
    }

    func testDetectedTargetsPickUpHomeEditorDirectories() throws {
        let home = root.appendingPathComponent("home", isDirectory: true)
        try FileManager.default.createDirectory(
            at: home.appendingPathComponent(".codeium/windsurf"),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: home.appendingPathComponent(".codex"),
            withIntermediateDirectories: true
        )
        let targets = AIEditorHookTarget.detectedTargets(repositoryPath: root, homeDirectory: home)
        XCTAssertEqual(targets, [.cursor, .claude, .windsurf, .codex])
    }

    func testDetectedTargetsIgnorePlainFilesWithEditorNames() throws {
        let home = root.appendingPathComponent("home", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        FileManager.default.createFile(
            atPath: home.appendingPathComponent(".codex").path,
            contents: Data()
        )
        let targets = AIEditorHookTarget.detectedTargets(repositoryPath: root, homeDirectory: home)
        XCTAssertEqual(targets, [.cursor, .claude])
    }

    func testInstallCursorWithShellGate() throws {
        let installer = AIEditorHookInstaller()
        let result = try installer.install(
            target: .cursor,
            repositoryPath: root,
            cliExecutablePath: "/usr/local/bin/offsend",
            withShellGate: true
        )
        XCTAssertTrue(result.withShellGate)
        let shellPath = try XCTUnwrap(result.shellWrapperPath)
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: shellPath))

        let data = try Data(contentsOf: URL(fileURLWithPath: result.configPath))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let hooks = try XCTUnwrap(object["hooks"] as? [String: Any])
        let shellHooks = try XCTUnwrap(hooks["beforeShellExecution"] as? [[String: Any]])
        XCTAssertTrue((shellHooks.first?["command"] as? String)?.contains("check-shell.sh") == true)
    }

    func testShellGateOffByDefaultAndReinstallRemoves() throws {
        let installer = AIEditorHookInstaller()
        _ = try installer.install(
            target: .cursor,
            repositoryPath: root,
            cliExecutablePath: "/usr/local/bin/offsend",
            withShellGate: true
        )
        // Reinstall without the shell gate removes the entry and the orphan wrapper.
        let result = try installer.install(
            target: .cursor,
            repositoryPath: root,
            cliExecutablePath: "/usr/local/bin/offsend"
        )
        XCTAssertFalse(result.withShellGate)
        XCTAssertNil(result.shellWrapperPath)

        let data = try Data(contentsOf: URL(fileURLWithPath: result.configPath))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let hooks = try XCTUnwrap(object["hooks"] as? [String: Any])
        XCTAssertNil(hooks["beforeShellExecution"])
        let shellURL = root.appendingPathComponent(AIEditorHookInstaller.shellWrapperRelativePath)
        XCTAssertFalse(FileManager.default.fileExists(atPath: shellURL.path))
    }

    func testInstallClaudeWithShellGateAddsBashMatcher() throws {
        let installer = AIEditorHookInstaller()
        let result = try installer.install(
            target: .claude,
            repositoryPath: root,
            cliExecutablePath: "/usr/local/bin/offsend",
            withShellGate: true
        )
        let data = try Data(contentsOf: URL(fileURLWithPath: result.configPath))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let hooks = try XCTUnwrap(object["hooks"] as? [String: Any])
        let preToolUse = try XCTUnwrap(hooks["PreToolUse"] as? [[String: Any]])
        let matchers = preToolUse.compactMap { $0["matcher"] as? String }
        XCTAssertTrue(matchers.contains("Read|Edit|Write"))
        XCTAssertTrue(matchers.contains("Bash"))

        try installer.uninstall(target: .claude, repositoryPath: root)
        let shellURL = root.appendingPathComponent(AIEditorHookInstaller.shellWrapperRelativePath)
        XCTAssertFalse(FileManager.default.fileExists(atPath: shellURL.path))
    }

    func testDefaultPolicies() {
        XCTAssertEqual(AIEditorHookInstaller.defaultHookPolicy(for: .cursor), .softBlock)
        XCTAssertEqual(AIEditorHookInstaller.defaultHookPolicy(for: .claude), .softBlock)
        XCTAssertEqual(AIEditorHookInstaller.defaultHookPolicy(for: .windsurf), .softBlock)
        XCTAssertEqual(AIEditorHookInstaller.defaultHookPolicy(for: .codex), .softBlock)
    }

    func testInstallCursorWithReadGate() throws {
        let installer = AIEditorHookInstaller()
        let result = try installer.install(
            target: .cursor,
            repositoryPath: root,
            cliExecutablePath: "/usr/local/bin/offsend",
            withReadGate: true
        )
        XCTAssertTrue(result.withReadGate)
        XCTAssertNotNil(result.readWrapperPath)
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: result.readWrapperPath!))

        let data = try Data(contentsOf: URL(fileURLWithPath: result.configPath))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let hooks = try XCTUnwrap(object["hooks"] as? [String: Any])
        XCTAssertNotNil(hooks["beforeSubmitPrompt"])
        let readHooks = try XCTUnwrap(hooks["beforeReadFile"] as? [[String: Any]])
        XCTAssertTrue((readHooks.first?["command"] as? String)?.contains("check-read.sh") == true)
    }

    func testReadGateOnByDefault() throws {
        let installer = AIEditorHookInstaller()
        let result = try installer.install(
            target: .cursor,
            repositoryPath: root,
            cliExecutablePath: "/usr/local/bin/offsend"
        )
        XCTAssertTrue(result.withReadGate)
        let data = try Data(contentsOf: URL(fileURLWithPath: result.configPath))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let hooks = try XCTUnwrap(object["hooks"] as? [String: Any])
        XCTAssertNotNil(hooks["beforeReadFile"])
    }

    func testReadGateOptOut() throws {
        let installer = AIEditorHookInstaller()
        let result = try installer.install(
            target: .cursor,
            repositoryPath: root,
            cliExecutablePath: "/usr/local/bin/offsend",
            withReadGate: false
        )
        XCTAssertFalse(result.withReadGate)
        let data = try Data(contentsOf: URL(fileURLWithPath: result.configPath))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let hooks = try XCTUnwrap(object["hooks"] as? [String: Any])
        XCTAssertNil(hooks["beforeReadFile"])
    }

    func testReinstallWithoutReadGateRemovesOrphanWrapper() throws {
        let installer = AIEditorHookInstaller()
        _ = try installer.install(
            target: .cursor,
            repositoryPath: root,
            cliExecutablePath: "/usr/local/bin/offsend",
            withReadGate: true
        )
        let readPath = root.appendingPathComponent(AIEditorHookInstaller.readWrapperRelativePath).path
        XCTAssertTrue(FileManager.default.fileExists(atPath: readPath))

        _ = try installer.install(
            target: .cursor,
            repositoryPath: root,
            cliExecutablePath: "/usr/local/bin/offsend",
            withReadGate: false
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: readPath))
    }

    /// Windsurf/codex install must not delete check-read.sh still referenced by cursor
    /// (JSON `\/` escaping previously made cleanup think the wrapper was unused).
    func testWindsurfInstallPreservesCursorReadGateWrapper() throws {
        let installer = AIEditorHookInstaller()
        _ = try installer.install(
            target: .cursor,
            repositoryPath: root,
            cliExecutablePath: "/usr/local/bin/offsend",
            withReadGate: true
        )
        let readURL = root.appendingPathComponent(AIEditorHookInstaller.readWrapperRelativePath)
        XCTAssertTrue(FileManager.default.fileExists(atPath: readURL.path))

        _ = try installer.install(
            target: .windsurf,
            repositoryPath: root,
            cliExecutablePath: "/usr/local/bin/offsend",
            withReadGate: true
        )
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: readURL.path),
            "check-read.sh must survive a subsequent windsurf install"
        )

        let status = installer.status(target: .cursor, repositoryPath: root)
        XCTAssertTrue(status.installed)
        XCTAssertFalse(status.broken)
    }

    /// Escaped-slash config text must still count as a reference (legacy writes).
    func testConfigTextReferencesHandlesJSONEscapedSlashes() {
        let path = AIEditorHookInstaller.readWrapperRelativePath
        let plain = #"{"command":".offsend/hooks/check-read.sh cursor"}"#
        let escaped = #"{"command":".offsend\/hooks\/check-read.sh cursor"}"#
        XCTAssertTrue(AIEditorHookInstaller.configTextReferences(plain, relativePath: path))
        XCTAssertTrue(AIEditorHookInstaller.configTextReferences(escaped, relativePath: path))
        XCTAssertFalse(
            AIEditorHookInstaller.configTextReferences(
                #"{"command":".offsend/hooks/check-prompt.sh"}"#,
                relativePath: path
            )
        )
    }

    func testWindsurfUsesWorkspaceHooksPath() {
        let url = AIEditorHookInstaller().configURL(for: .windsurf, repositoryPath: root)
        XCTAssertTrue(url.path.hasSuffix(".windsurf/hooks.json"))
    }
}

final class SealCopyStoreTests: XCTestCase {
    func testWritesPrivateFile() throws {
        let result = try SealCopyStore.write("{{SECRET:v1.abc}}")
        defer { try? FileManager.default.removeItem(at: result.fileURL.deletingLastPathComponent()) }

        let attrs = try FileManager.default.attributesOfItem(atPath: result.fileURL.path)
        let perms = attrs[.posixPermissions] as? NSNumber
        XCTAssertEqual(perms?.intValue ?? 0, 0o600)
        XCTAssertEqual(try String(contentsOf: result.fileURL, encoding: .utf8), "{{SECRET:v1.abc}}")
    }
}

final class PromptAttachmentAdvisorTests: XCTestCase {
    func testDetectsEnvAndPemAttachments() {
        let paths = ["/tmp/notes.txt", "/repo/.env.local", "/keys/id.pem"]
        let suspicious = PromptAttachmentAdvisor.suspiciousPaths(in: paths)
        XCTAssertEqual(Set(suspicious), Set(["/repo/.env.local", "/keys/id.pem"]))
    }

    func testDoesNotFalsePositiveOnCamelCaseCredentials() {
        XCTAssertFalse(PromptAttachmentAdvisor.isSuspicious(path: "/src/CredentialsForm.tsx"))
        XCTAssertTrue(PromptAttachmentAdvisor.isSuspicious(path: "/config/credentials.json"))
        XCTAssertTrue(PromptAttachmentAdvisor.isSuspicious(path: "/secrets/api.key"))
    }

    func testDetectsSensitiveDirectoryComponents() {
        XCTAssertTrue(PromptAttachmentAdvisor.isSuspicious(path: "/Users/me/.kube/config"))
        XCTAssertTrue(PromptAttachmentAdvisor.isSuspicious(path: #"C:\Users\me\.docker\config.json"#))
        XCTAssertTrue(PromptAttachmentAdvisor.isSuspicious(path: "/home/me/.aws/config"))
        XCTAssertTrue(PromptAttachmentAdvisor.isSuspicious(path: "/home/me/.gnupg/pubring.kbx"))
    }

    func testDoesNotMatchSimilarOrdinaryDirectories() {
        XCTAssertFalse(PromptAttachmentAdvisor.isSuspicious(path: "/repo/kube/config"))
        XCTAssertFalse(PromptAttachmentAdvisor.isSuspicious(path: "/repo/docker/config.json"))
        XCTAssertFalse(PromptAttachmentAdvisor.isSuspicious(path: "/repo/.dockerignore"))
    }
}

final class HookDebugLogTests: XCTestCase {
    func testSanitizeLogTextRedactsHomeDirectory() {
        let home = NSHomeDirectory()
        let sanitized = HookDebugLog.sanitizeLogText("settings at \(home)/Library")
        XCTAssertFalse(sanitized.contains(home))
        XCTAssertTrue(sanitized.contains("~/Library"))
    }

    func testRotatesWhenTooLarge() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("offsend-debug-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let url = dir.appendingPathComponent("hook-debug.log")
        let big = String(repeating: "x", count: 1000)
        try big.write(to: url, atomically: true, encoding: .utf8)
        HookDebugLog.rotateIfNeeded(at: url, maxBytes: 100)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.appendingPathExtension("1").path))
    }
}
