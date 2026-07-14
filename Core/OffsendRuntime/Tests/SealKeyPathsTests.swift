import Foundation
import MaskingCore
import XCTest
@testable import OffsendRuntime

final class SealKeyPathsTests: XCTestCase {
    private var tempHome: URL!
    private var savedHome: String?

    override func setUpWithError() throws {
        tempHome = FileManager.default.temporaryDirectory
            .appendingPathComponent("offsend-home-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempHome, withIntermediateDirectories: true)
        savedHome = getenv("HOME").map { String(cString: $0) }
        setenv("HOME", tempHome.path, 1)
    }

    override func tearDownWithError() throws {
        if let savedHome {
            setenv("HOME", savedHome, 1)
        } else {
            unsetenv("HOME")
        }
        try? FileManager.default.removeItem(at: tempHome)
    }

    func testDefaultKeyURLUnderHome() {
        let url = SealKeyPaths.defaultKeyURL()
        XCTAssertTrue(url.path.hasSuffix("/.offsend/seal.key"))
    }

    func testNamedKeyURLSanitizesName() throws {
        let url = try SealKeyPaths.namedKeyURL(name: "work")
        XCTAssertTrue(url.path.hasSuffix("/.offsend/keys/work.key"))
    }

    func testRejectsInvalidKeyName() {
        XCTAssertThrowsError(try SealKeyPaths.namedKeyURL(name: "../escape")) { error in
            guard case SealError.invalidKey = error else {
                return XCTFail("Expected invalidKey, got \(error)")
            }
        }
        XCTAssertThrowsError(try SealKeyPaths.namedKeyURL(name: ".."))
        XCTAssertThrowsError(try SealKeyPaths.namedKeyURL(name: ".hidden"))
    }

    func testWriteKeyDoesNotChmodUnmanagedParent() throws {
        let parent = tempHome.appendingPathComponent("outdir", isDirectory: true)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: parent.path)

        let keyURL = parent.appendingPathComponent("custom.key")
        let keyData = Data((0..<32).map { UInt8($0) })
        try SealKeyPaths.writeKey(
            keyData,
            to: keyURL,
            raw: false,
            force: false,
            environment: ["HOME": tempHome.path]
        )

        let parentMode = try FileManager.default.attributesOfItem(atPath: parent.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(parentMode?.uint16Value, 0o755)
    }

    func testWriteKeyRefusesSymlink() throws {
        let target = tempHome.appendingPathComponent("real.key")
        let link = SealKeyPaths.defaultKeyURL(environment: ["HOME": tempHome.path])
        try FileManager.default.createDirectory(
            at: link.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data([1]).write(to: target)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

        XCTAssertThrowsError(
            try SealKeyPaths.writeKey(
                Data((0..<32).map { UInt8($0) }),
                to: link,
                raw: false,
                force: true,
                environment: ["HOME": tempHome.path]
            )
        ) { error in
            guard case SealError.invalidKey(let reason) = error else {
                return XCTFail("Expected invalidKey, got \(error)")
            }
            XCTAssertTrue(reason.contains("symlink"))
        }
    }

    func testWriteKeyRefusesOverwrite() throws {
        let keyData = Data((0..<32).map { UInt8($0) })
        let url = SealKeyPaths.defaultKeyURL()
        try SealKeyPaths.writeKey(keyData, to: url, raw: false, force: false)

        XCTAssertThrowsError(
            try SealKeyPaths.writeKey(Data((32..<64).map { UInt8($0) }), to: url, raw: false, force: false)
        ) { error in
            guard case SealError.invalidKey(let reason) = error else {
                return XCTFail("Expected invalidKey, got \(error)")
            }
            XCTAssertTrue(reason.contains("already exists"))
        }
    }

    func testWriteKeyAllowsOverwriteWithForce() throws {
        let first = Data((0..<32).map { UInt8($0) })
        let second = Data((32..<64).map { UInt8($0) })
        let url = SealKeyPaths.defaultKeyURL()
        try SealKeyPaths.writeKey(first, to: url, raw: false, force: false)
        try SealKeyPaths.writeKey(second, to: url, raw: false, force: true)

        let resolved = try SealKeyResolver.resolve(key: nil, keyFilePath: nil, environment: ["HOME": tempHome.path])
        XCTAssertEqual(resolved.data, second)
    }

    func testWriteKeyCreatesDirectoriesWithRestrictedPermissions() throws {
        let keyData = Data((0..<32).map { UInt8($0) })
        let url = try SealKeyPaths.namedKeyURL(name: "ci")
        try SealKeyPaths.writeKey(keyData, to: url, raw: false, force: false)

        let homeAttributes = try FileManager.default.attributesOfItem(atPath: SealKeyPaths.homeDirectory().path)
        let keyAttributes = try FileManager.default.attributesOfItem(atPath: url.path)
        XCTAssertEqual((homeAttributes[.posixPermissions] as? NSNumber)?.uint16Value, 0o700)
        XCTAssertEqual((keyAttributes[.posixPermissions] as? NSNumber)?.uint16Value, 0o600)
    }

    func testCountNamedKeys() throws {
        XCTAssertEqual(SealKeyPaths.countNamedKeys(), 0)
        let keyData = Data((0..<32).map { UInt8($0) })
        try SealKeyPaths.writeKey(
            keyData,
            to: try SealKeyPaths.namedKeyURL(name: "a"),
            raw: false,
            force: false
        )
        try SealKeyPaths.writeKey(
            keyData,
            to: try SealKeyPaths.namedKeyURL(name: "b"),
            raw: false,
            force: false
        )
        XCTAssertEqual(SealKeyPaths.countNamedKeys(), 2)
    }

    func testInsecurePermissionWarning() throws {
        let url = SealKeyPaths.defaultKeyURL(environment: ["HOME": tempHome.path])
        try SealKeyPaths.writeKey(
            Data((0..<32).map { UInt8($0) }),
            to: url,
            raw: false,
            force: false,
            environment: ["HOME": tempHome.path]
        )
        XCTAssertNil(SealKeyPaths.insecurePermissionWarning(at: url))

        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path)
        let warning = SealKeyPaths.insecurePermissionWarning(at: url)
        XCTAssertNotNil(warning)
        XCTAssertTrue(warning?.contains("644") == true)
    }

    func testSealAvailabilityHintDistinguishesExplicitKey() {
        let missing = SealError.invalidKey(
            "provide --key, --key-file, --key-name, set OFFSEND_SEAL_KEY, or run: \(SealKeyPaths.defaultKeyInstallHint)"
        )
        let missingHint = SealAvailabilityHint.stderrMessage(
            error: missing,
            key: nil,
            keyFile: nil,
            keyName: nil
        )
        XCTAssertTrue(missingHint.contains("keygen --default"))

        let badFile = SealError.invalidKey("could not read key file at /tmp/bad.key")
        let badHint = SealAvailabilityHint.stderrMessage(
            error: badFile,
            key: nil,
            keyFile: "/tmp/bad.key",
            keyName: nil
        )
        XCTAssertTrue(badHint.contains("could not read"))
        XCTAssertFalse(badHint.contains("keygen --default"))
    }
}
