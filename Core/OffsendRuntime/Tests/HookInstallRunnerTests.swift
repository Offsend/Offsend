import XCTest
@testable import OffsendRuntime

final class HookInstallRunnerTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("offsend-hook-runner-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent(".git/hooks", isDirectory: true),
            withIntermediateDirectories: true
        )
        try writeConfig(
            """
            version: 1
            ignore:
              commit: true
              patterns:
                - "secrets/"
            hooks:
              type: pre-commit
              publish: false
            """
        )
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testInstallGitHookWritesManagedHook() throws {
        let outcome = try HookInstallRunner.installGitHook(
            repositoryURL: root,
            executable: "/tmp/offsend",
            tolerateFailure: false
        )
        XCTAssertNil(outcome.warning)
        let hookURL = try XCTUnwrap(outcome.hookURL)
        let contents = try String(contentsOf: hookURL, encoding: .utf8)
        XCTAssertTrue(contents.contains(OffsendCLILocator.managedHookMarker))
        XCTAssertTrue(contents.contains("OFFSEND_BIN=/tmp/offsend"))
    }

    func testInstallGitHookToleratesForeignHook() throws {
        let hookURL = root.appendingPathComponent(".git/hooks/pre-commit")
        try "#!/bin/sh\necho custom\n".write(to: hookURL, atomically: true, encoding: .utf8)

        let outcome = try HookInstallRunner.installGitHook(
            repositoryURL: root,
            executable: "/tmp/offsend",
            tolerateFailure: true
        )
        XCTAssertNil(outcome.hookURL)
        XCTAssertNotNil(outcome.warning)
        XCTAssertTrue(try String(contentsOf: hookURL, encoding: .utf8).contains("custom"))
    }

    func testInstallGitHookThrowsForeignHookWhenNotTolerated() throws {
        let hookURL = root.appendingPathComponent(".git/hooks/pre-commit")
        try "#!/bin/sh\necho custom\n".write(to: hookURL, atomically: true, encoding: .utf8)

        XCTAssertThrowsError(
            try HookInstallRunner.installGitHook(
                repositoryURL: root,
                executable: "/tmp/offsend",
                tolerateFailure: false
            )
        ) { error in
            XCTAssertEqual(error as? HookManagerError, .hookAlreadyInstalled(path: hookURL.path))
        }
    }

    func testInstallAIHooksUpdatesLocalExcludeWhenPublishFalse() throws {
        let outcome = try HookInstallRunner.installAIHooks(
            [.cursor],
            repositoryURL: root,
            executable: "/tmp/offsend",
            withReadGate: false,
            withShellGate: false,
            withMCPGate: false,
            withSubagentGate: false
        )
        XCTAssertEqual(outcome.results.count, 1)
        XCTAssertEqual(outcome.results[0].target, .cursor)
        XCTAssertFalse(outcome.publishHooks)
        XCTAssertTrue(outcome.excludeUpdated)

        let exclude = root.appendingPathComponent(".git/info/exclude")
        XCTAssertTrue(FileManager.default.fileExists(atPath: exclude.path))
        let excludeText = try String(contentsOf: exclude, encoding: .utf8)
        XCTAssertTrue(excludeText.contains(".cursor/hooks.json"))
    }

    func testInstallAIHooksSkipsExcludeWhenPublishTrue() throws {
        try writeConfig(
            """
            version: 1
            ignore:
              commit: true
              patterns: []
            hooks:
              publish: true
            """
        )
        let outcome = try HookInstallRunner.installAIHooks(
            [.cursor],
            repositoryURL: root,
            executable: "/tmp/offsend",
            withReadGate: false,
            withShellGate: false,
            withMCPGate: false,
            withSubagentGate: false
        )
        XCTAssertTrue(outcome.publishHooks)
        XCTAssertFalse(outcome.excludeUpdated)
    }

    func testInstallAIHooksFailsOnForeignWrapperWithoutForce() throws {
        let wrapper = root.appendingPathComponent(AIEditorHookInstaller.wrapperRelativePath)
        try FileManager.default.createDirectory(
            at: wrapper.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "#!/bin/sh\necho custom-wrapper\n".write(to: wrapper, atomically: true, encoding: .utf8)

        XCTAssertThrowsError(
            try HookInstallRunner.installAIHooks(
                [.cursor],
                repositoryURL: root,
                executable: "/tmp/offsend",
                withReadGate: false,
                withShellGate: false,
                withMCPGate: false,
                withSubagentGate: false
            )
        ) { error in
            let failure = error as? HookInstallRunner.AIHookFailure
            XCTAssertEqual(failure?.target, .cursor)
            XCTAssertNotNil(failure?.message)
        }
        XCTAssertTrue(try String(contentsOf: wrapper, encoding: .utf8).contains("custom-wrapper"))
    }

    private func writeConfig(_ yaml: String) throws {
        try yaml.write(
            to: root.appendingPathComponent(ProjectConfigLoader.filename),
            atomically: true,
            encoding: .utf8
        )
    }
}
