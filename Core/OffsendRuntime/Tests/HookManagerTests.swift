import XCTest
@testable import OffsendRuntime

final class HookManagerTests: XCTestCase {
    func testInstallWritesManagedPreCommitHook() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent(".git/hooks", isDirectory: true),
            withIntermediateDirectories: true
        )

        let manager = HookManager()
        let hookURL = try manager.install(
            HookInstallOptions(
                repositoryPath: root,
                cliExecutablePath: "/tmp/offsend"
            )
        )

        let contents = try String(contentsOf: hookURL, encoding: .utf8)
        XCTAssertTrue(contents.contains(OffsendCLILocator.managedHookMarker))
        XCTAssertTrue(contents.contains("OFFSEND_BIN=/tmp/offsend"))
        XCTAssertTrue(contents.contains("exec \"$OFFSEND_BIN\" check --staged"))
        XCTAssertTrue(contents.contains("--fail-on"))
        XCTAssertTrue(contents.contains("block"))
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: hookURL.path))
        XCTAssertTrue(try manager.isInstalled(repositoryPath: root))
    }

    func testInstallCreatesHooksDirectoryWhenMissing() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try FileManager.default.createDirectory(
            at: root.appendingPathComponent(".git", isDirectory: true),
            withIntermediateDirectories: true
        )

        let manager = HookManager()
        let hookURL = try manager.install(
            HookInstallOptions(
                repositoryPath: root,
                cliExecutablePath: "/tmp/offsend"
            )
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: hookURL.path))
    }

    func testInstallFailsWhenForeignHookExists() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let hooksDirectory = root.appendingPathComponent(".git/hooks", isDirectory: true)
        try FileManager.default.createDirectory(at: hooksDirectory, withIntermediateDirectories: true)
        let hookURL = hooksDirectory.appendingPathComponent("pre-commit")
        try "#!/bin/sh\necho custom\n".write(to: hookURL, atomically: true, encoding: .utf8)

        let manager = HookManager()
        XCTAssertThrowsError(
            try manager.install(
                HookInstallOptions(
                    repositoryPath: root,
                    cliExecutablePath: "/tmp/offsend"
                )
            )
        ) { error in
            XCTAssertEqual(error as? HookManagerError, .hookAlreadyInstalled(path: hookURL.path))
        }
    }

    func testUninstallRemovesManagedHook() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try FileManager.default.createDirectory(
            at: root.appendingPathComponent(".git/hooks", isDirectory: true),
            withIntermediateDirectories: true
        )

        let manager = HookManager()
        _ = try manager.install(
            HookInstallOptions(
                repositoryPath: root,
                cliExecutablePath: "/tmp/offsend"
            )
        )
        try manager.uninstall(repositoryPath: root)
        XCTAssertFalse(try manager.isInstalled(repositoryPath: root))
    }

    func testForeignHookMentioningMarkerInBodyIsNotManaged() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let hooksDirectory = root.appendingPathComponent(".git/hooks", isDirectory: true)
        try FileManager.default.createDirectory(at: hooksDirectory, withIntermediateDirectories: true)
        let hookURL = hooksDirectory.appendingPathComponent("pre-commit")
        try "#!/bin/sh\necho run\n# wraps \(OffsendCLILocator.managedHookMarker) script\n"
            .write(to: hookURL, atomically: true, encoding: .utf8)

        let manager = HookManager()
        XCTAssertThrowsError(
            try manager.install(
                HookInstallOptions(repositoryPath: root, cliExecutablePath: "/tmp/offsend")
            )
        ) { error in
            XCTAssertEqual(error as? HookManagerError, .hookAlreadyInstalled(path: hookURL.path))
        }
        XCTAssertThrowsError(try manager.uninstall(repositoryPath: root)) { error in
            XCTAssertEqual(error as? HookManagerError, .hookModified(path: hookURL.path))
        }
    }

    func testIsManagedHookScriptChecksLeadingLines() {
        XCTAssertTrue(
            HookManager.isManagedHookScript("#!/bin/sh\n\(OffsendCLILocator.managedHookMarker) v1\nexec offsend\n")
        )
        XCTAssertFalse(
            HookManager.isManagedHookScript("#!/bin/sh\necho hi\n\(OffsendCLILocator.managedHookMarker) v1\n")
        )
    }

    func testHookScriptIncludesPolicyFlagWhenRequested() {
        let manager = HookManager()
        let script = manager.makeHookScript(
            options: HookInstallOptions(
                repositoryPath: URL(fileURLWithPath: "/tmp/repo"),
                includePolicyCheck: true,
                cliExecutablePath: "/Applications/Offsend.app/Contents/Helpers/offsend"
            )
        )
        XCTAssertTrue(script.contains("--policy"))
    }
}
