#if os(macOS)
import XCTest
@testable import OffsendRuntime

final class CLIPathInstallerTests: XCTestCase {
    func testStatusIsNotInstalledWhenCommandAndTargetAreMissing() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let appCLI = try makeExecutable(at: root.appendingPathComponent("Offsend.app/Contents/Helpers/offsend"))
        let installer = CLIPathInstaller(
            bundledCLIPath: appCLI.path,
            installPath: root.appendingPathComponent("bin/offsend").path,
            pathEnvironment: root.appendingPathComponent("bin").path,
            includeDefaultSearchPaths: false,
            runPrivilegedShell: { _ in }
        )

        XCTAssertEqual(installer.status().state, .notInstalled)
    }

    func testStatusIsInstalledWhenCommandPointsToBundledCLI() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let appCLI = try makeExecutable(at: root.appendingPathComponent("Offsend.app/Contents/Helpers/offsend"))
        let binDirectory = root.appendingPathComponent("bin", isDirectory: true)
        try FileManager.default.createDirectory(at: binDirectory, withIntermediateDirectories: true)
        let command = binDirectory.appendingPathComponent("offsend")
        try FileManager.default.createSymbolicLink(at: command, withDestinationURL: appCLI)

        let installer = CLIPathInstaller(
            bundledCLIPath: appCLI.path,
            installPath: command.path,
            pathEnvironment: binDirectory.path,
            includeDefaultSearchPaths: false,
            runPrivilegedShell: { _ in }
        )

        let status = installer.status()
        XCTAssertEqual(status.state, .installed)
        XCTAssertEqual(status.commandPath, command.path)
        XCTAssertEqual(status.commandTargetPath, appCLI.path)
    }

    func testStatusDetectsHomebrewCLIWithoutOverwritingIt() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let appCLI = try makeExecutable(at: root.appendingPathComponent("Offsend.app/Contents/Helpers/offsend"))
        let brewCellarCLI = try makeExecutable(
            at: root.appendingPathComponent("Caskroom/offsend-cli/1.2.3/offsend")
        )
        let brewBin = root.appendingPathComponent("homebrew/bin", isDirectory: true)
        try FileManager.default.createDirectory(at: brewBin, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: brewBin.appendingPathComponent("offsend"),
            withDestinationURL: brewCellarCLI
        )

        let installer = CLIPathInstaller(
            bundledCLIPath: appCLI.path,
            installPath: root.appendingPathComponent("usr/local/bin/offsend").path,
            pathEnvironment: brewBin.path,
            includeDefaultSearchPaths: false,
            runPrivilegedShell: { _ in }
        )

        XCTAssertEqual(installer.status().state, .availableViaHomebrew)
        XCTAssertThrowsError(try installer.install()) { error in
            XCTAssertEqual(error as? CLIPathInstallerError, .commandAlreadyAvailable(path: brewBin.appendingPathComponent("offsend").path))
        }
    }

    func testInstallPathBlockedByForeignExecutable() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let appCLI = try makeExecutable(at: root.appendingPathComponent("Offsend.app/Contents/Helpers/offsend"))
        let installPath = try makeExecutable(at: root.appendingPathComponent("usr/local/bin/offsend"))

        let installer = CLIPathInstaller(
            bundledCLIPath: appCLI.path,
            installPath: installPath.path,
            pathEnvironment: root.appendingPathComponent("empty-bin").path,
            includeDefaultSearchPaths: false,
            runPrivilegedShell: { _ in }
        )

        XCTAssertEqual(installer.status().state, .targetBlocked)
        XCTAssertThrowsError(try installer.install()) { error in
            XCTAssertEqual(error as? CLIPathInstallerError, .installPathBlocked(path: installPath.path))
        }
    }

    func testStatusDetectsShadowingManagedInstallWhenHomebrewResolvesFirst() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let appCLI = try makeExecutable(at: root.appendingPathComponent("Offsend.app/Contents/Helpers/offsend"))
        let brewCellarCLI = try makeExecutable(
            at: root.appendingPathComponent("Caskroom/offsend-cli/1.2.3/offsend")
        )
        let brewBin = root.appendingPathComponent("homebrew/bin", isDirectory: true)
        let localBin = root.appendingPathComponent("usr/local/bin", isDirectory: true)
        try FileManager.default.createDirectory(at: brewBin, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: localBin, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: brewBin.appendingPathComponent("offsend"),
            withDestinationURL: brewCellarCLI
        )
        let managedCommand = localBin.appendingPathComponent("offsend")
        try FileManager.default.createSymbolicLink(at: managedCommand, withDestinationURL: appCLI)

        let installer = CLIPathInstaller(
            bundledCLIPath: appCLI.path,
            installPath: managedCommand.path,
            pathEnvironment: "\(brewBin.path):\(localBin.path)",
            includeDefaultSearchPaths: false,
            runPrivilegedShell: { _ in }
        )

        let status = installer.status()
        XCTAssertEqual(status.state, .availableViaHomebrew)
        XCTAssertEqual(status.commandPath, brewBin.appendingPathComponent("offsend").path)
        XCTAssertEqual(status.shadowingManagedInstallPath, managedCommand.path)
    }

    func testInstallRunsPrivilegedScriptWhenTargetIsFree() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let appCLI = try makeExecutable(at: root.appendingPathComponent("Offsend.app/Contents/Helpers/offsend"))
        let scriptCapture = ScriptCapture()
        let installPath = root.appendingPathComponent("usr/local/bin/offsend")

        let installer = CLIPathInstaller(
            bundledCLIPath: appCLI.path,
            installPath: installPath.path,
            pathEnvironment: root.appendingPathComponent("empty-bin").path,
            includeDefaultSearchPaths: false,
            runPrivilegedShell: { script in
                scriptCapture.value = script
            }
        )

        try installer.install()
        XCTAssertTrue(scriptCapture.value?.contains("ln -s \(appCLI.path) \(installPath.path)") == true)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @discardableResult
    private func makeExecutable(at url: URL) throws -> URL {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "#!/bin/sh\n".write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }
}

private final class ScriptCapture: @unchecked Sendable {
    var value: String?
}
#endif
