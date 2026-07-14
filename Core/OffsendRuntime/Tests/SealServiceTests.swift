import DetectionCore
import Foundation
import MaskingCore
import XCTest
@testable import OffsendRuntime

final class SealKeyResolverTests: XCTestCase {
    func testResolvesFlagKey() throws {
        let keyData = Data((0..<32).map { UInt8($0) })
        let b64 = keyData.base64EncodedString()
        let resolved = try SealKeyResolver.resolve(key: b64, keyFilePath: nil, environment: [:])
        XCTAssertEqual(resolved.data, keyData)
        XCTAssertEqual(resolved.source, .flagKey)
    }

    func testRejectsMultipleKeySources() {
        XCTAssertThrowsError(
            try SealKeyResolver.resolve(key: "abc", keyFilePath: "/tmp/k", environment: [:])
        ) { error in
            guard case SealError.invalidKey(let reason) = error else {
                return XCTFail("Expected invalidKey, got \(error)")
            }
            XCTAssertTrue(reason.contains("only one of"))
        }
    }

    func testRejectsKeyFileAndKeyName() {
        XCTAssertThrowsError(
            try SealKeyResolver.resolve(key: nil, keyFilePath: "/tmp/k", keyName: "work", environment: [:])
        ) { error in
            guard case SealError.invalidKey(let reason) = error else {
                return XCTFail("Expected invalidKey, got \(error)")
            }
            XCTAssertTrue(reason.contains("only one of"))
        }
    }

    func testResolvesDefaultKeyFile() throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("offsend-home-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }

        let savedHome = getenv("HOME").map { String(cString: $0) }
        setenv("HOME", home.path, 1)
        defer {
            if let savedHome {
                setenv("HOME", savedHome, 1)
            } else {
                unsetenv("HOME")
            }
        }

        let keyData = Data((0..<32).map { UInt8($0) })
        try SealKeyPaths.writeKey(keyData, to: SealKeyPaths.defaultKeyURL(), raw: false, force: false)

        let resolved = try SealKeyResolver.resolve(
            key: nil,
            keyFilePath: nil,
            environment: ["HOME": home.path]
        )
        XCTAssertEqual(resolved.data, keyData)
        XCTAssertEqual(resolved.source, .defaultFile)
    }

    func testEnvironmentTakesPriorityOverDefaultFile() throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("offsend-home-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }

        let savedHome = getenv("HOME").map { String(cString: $0) }
        setenv("HOME", home.path, 1)
        defer {
            if let savedHome {
                setenv("HOME", savedHome, 1)
            } else {
                unsetenv("HOME")
            }
        }

        let fileKey = Data((0..<32).map { UInt8($0) })
        let envKey = Data((32..<64).map { UInt8($0) })
        try SealKeyPaths.writeKey(fileKey, to: SealKeyPaths.defaultKeyURL(), raw: false, force: false)

        let resolved = try SealKeyResolver.resolve(
            key: nil,
            keyFilePath: nil,
            environment: [SealKeyResolver.environmentVariable: envKey.base64EncodedString()]
        )
        XCTAssertEqual(resolved.data, envKey)
        XCTAssertEqual(resolved.source, .environment)
    }

    func testResolvesNamedKey() throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("offsend-home-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }

        let savedHome = getenv("HOME").map { String(cString: $0) }
        setenv("HOME", home.path, 1)
        defer {
            if let savedHome {
                setenv("HOME", savedHome, 1)
            } else {
                unsetenv("HOME")
            }
        }

        let keyData = Data((0..<32).map { UInt8($0) })
        try SealKeyPaths.writeKey(
            keyData,
            to: try SealKeyPaths.namedKeyURL(name: "work"),
            raw: false,
            force: false
        )

        let resolved = try SealKeyResolver.resolve(
            key: nil,
            keyFilePath: nil,
            keyName: "work",
            environment: ["HOME": home.path]
        )
        XCTAssertEqual(resolved.data, keyData)
        XCTAssertEqual(resolved.source, .keyName)
    }

    func testFallsBackToEnvironment() throws {
        let keyData = Data((0..<32).map { UInt8($0) })
        let b64 = keyData.base64EncodedString()
        let resolved = try SealKeyResolver.resolve(
            key: nil,
            keyFilePath: nil,
            environment: [SealKeyResolver.environmentVariable: b64]
        )
        XCTAssertEqual(resolved.data, keyData)
        XCTAssertEqual(resolved.source, .environment)
    }

    func testMissingKeyFails() {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("offsend-home-\(UUID().uuidString)", isDirectory: true)
        XCTAssertThrowsError(
            try SealKeyResolver.resolve(
                key: nil,
                keyFilePath: nil,
                environment: ["HOME": home.path]
            )
        ) { error in
            guard case SealError.invalidKey = error else {
                return XCTFail("Expected invalidKey, got \(error)")
            }
        }
    }

    func testLoadsRawKeyFile() throws {
        let keyData = Data((0..<32).map { UInt8($0) })
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("offsend-seal-key-\(UUID().uuidString)")
        try keyData.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let resolved = try SealKeyResolver.resolve(
            key: nil,
            keyFilePath: url.path,
            environment: [:]
        )
        XCTAssertEqual(resolved.data, keyData)
        XCTAssertEqual(resolved.source, .keyFile)
    }

    func testFlagKeyTakesPriorityOverEnvironment() throws {
        let flagKey = Data((0..<32).map { UInt8($0) })
        let envKey = Data((32..<64).map { UInt8($0) })
        let resolved = try SealKeyResolver.resolve(
            key: flagKey.base64EncodedString(),
            keyFilePath: nil,
            environment: [SealKeyResolver.environmentVariable: envKey.base64EncodedString()]
        )
        XCTAssertEqual(resolved.data, flagKey)
        XCTAssertEqual(resolved.source, .flagKey)
    }

    func testGenerateProducesUnique32ByteKeys() throws {
        let a = SealKeyResolver.generate()
        let b = SealKeyResolver.generate()
        XCTAssertEqual(a.count, SealKeyResolver.keyByteCount)
        XCTAssertEqual(b.count, SealKeyResolver.keyByteCount)
        XCTAssertNotEqual(a, b)

        let resolved = try SealKeyResolver.resolve(
            key: a.base64EncodedString(),
            keyFilePath: nil,
            environment: [:]
        )
        XCTAssertEqual(resolved.data, a)
    }

    func testLoadsBase64KeyFile() throws {
        let keyData = Data((0..<32).map { UInt8($0) })
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("offsend-seal-key-b64-\(UUID().uuidString)")
        try (keyData.base64EncodedString() + "\n").write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let resolved = try SealKeyResolver.resolve(
            key: nil,
            keyFilePath: url.path,
            environment: [:]
        )
        XCTAssertEqual(resolved.data, keyData)
        XCTAssertEqual(resolved.source, .keyFile)
    }

    func testRejectsMissingKeyFile() {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("offsend-missing-seal-key-\(UUID().uuidString)").path
        XCTAssertThrowsError(
            try SealKeyResolver.resolve(key: nil, keyFilePath: path, environment: [:])
        ) { error in
            guard case SealError.invalidKey(let reason) = error else {
                return XCTFail("Expected invalidKey, got \(error)")
            }
            XCTAssertTrue(reason.contains("could not read"))
        }
    }

    func testRejectsInvalidBase64Key() {
        XCTAssertThrowsError(
            try SealKeyResolver.resolve(key: "not-base64!!!", keyFilePath: nil, environment: [:])
        ) { error in
            guard case SealError.invalidKey(let reason) = error else {
                return XCTFail("Expected invalidKey, got \(error)")
            }
            XCTAssertTrue(reason.contains("base64"))
        }
    }

    func testRejectsWrongLengthKey() {
        let short = Data([1, 2, 3]).base64EncodedString()
        XCTAssertThrowsError(
            try SealKeyResolver.resolve(key: short, keyFilePath: nil, environment: [:])
        ) { error in
            guard case SealError.invalidKey(let reason) = error else {
                return XCTFail("Expected invalidKey, got \(error)")
            }
            XCTAssertTrue(reason.contains("32 bytes"))
        }
    }

    func testEmptyEnvironmentKeyFails() {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("offsend-home-\(UUID().uuidString)", isDirectory: true)
        XCTAssertThrowsError(
            try SealKeyResolver.resolve(
                key: nil,
                keyFilePath: nil,
                environment: [
                    "HOME": home.path,
                    SealKeyResolver.environmentVariable: "",
                ]
            )
        ) { error in
            guard case SealError.invalidKey = error else {
                return XCTFail("Expected invalidKey, got \(error)")
            }
        }
    }
}

final class OffsendSealServiceTests: XCTestCase {
    func testSealAndUnsealRoundTrip() async throws {
        let keyData = Data((0..<32).map { UInt8($0) })
        let context = OffsendRuntimeContext(settings: .default, customDictionaries: [])
        let service = OffsendSealService(context: context)
        let text = "Contact us at leaked@example.com"

        let sealed = try await service.seal(
            OffsendSealRequest(text: text, keyData: keyData)
        )
        XCTAssertGreaterThan(sealed.sealedCount, 0)
        XCTAssertFalse(sealed.sealedText.contains("leaked@example.com"))

        let restored = try service.unseal(text: sealed.sealedText, keyData: keyData)
        XCTAssertEqual(restored, text)
    }

    func testSealWithPreDetectedEntities() throws {
        let keyData = Data((0..<32).map { UInt8($0) })
        let text = "mail leaked@example.com"
        guard let range = text.range(of: "leaked@example.com") else {
            return XCTFail("missing email")
        }
        let entity = SensitiveEntity(
            type: .email,
            range: range,
            value: "leaked@example.com",
            confidence: 1,
            source: .regex
        )

        let service = OffsendSealService()
        let sealed = try service.seal(text: text, entities: [entity], keyData: keyData)
        XCTAssertEqual(sealed.sealedCount, 1)
        XCTAssertTrue(SealTokenDetector.containsSealTokens(in: sealed.sealedText))

        let restored = try service.unseal(text: sealed.sealedText, keyData: keyData)
        XCTAssertEqual(restored, text)
    }

    func testSealRequestFailsClosedOnOversizedEntity() {
        let keyData = Data((0..<32).map { UInt8($0) })
        let large = String(repeating: "x", count: 300)
        let text = "token \(large)"
        guard let range = text.range(of: large) else {
            return XCTFail("missing large value")
        }
        let entity = SensitiveEntity(
            type: .highEntropyString,
            range: range,
            value: large,
            confidence: 1,
            source: .secret
        )
        let service = OffsendSealService()

        XCTAssertThrowsError(
            try service.seal(
                text: text,
                entities: [entity],
                keyData: keyData,
                maxPlaintextBytes: 256
            )
        ) { error in
            XCTAssertEqual(error as? SealError, .plaintextTooLarge(byteCount: 300, limit: 256))
        }
    }

    func testSealRequestHonorsRaisedLimit() throws {
        let keyData = Data((0..<32).map { UInt8($0) })
        let large = String(repeating: "y", count: 300)
        let text = "secret \(large)"
        guard let range = text.range(of: large) else {
            return XCTFail("missing large value")
        }
        let entity = SensitiveEntity(
            type: .highEntropyString,
            range: range,
            value: large,
            confidence: 1,
            source: .secret
        )

        let service = OffsendSealService()
        let sealed = try service.seal(
            text: text,
            entities: [entity],
            keyData: keyData,
            maxPlaintextBytes: 512
        )
        XCTAssertEqual(sealed.sealedCount, 1)
        XCTAssertFalse(sealed.sealedText.contains(large))

        let restored = try service.unseal(text: sealed.sealedText, keyData: keyData)
        XCTAssertEqual(restored, text)
    }

    func testUnsealWithWrongKeyFails() throws {
        let keyData = Data((0..<32).map { UInt8($0) })
        let otherKey = Data((32..<64).map { UInt8($0) })
        let text = "mail leaked@example.com"
        guard let range = text.range(of: "leaked@example.com") else {
            return XCTFail("missing email")
        }
        let entity = SensitiveEntity(
            type: .email,
            range: range,
            value: "leaked@example.com",
            confidence: 1,
            source: .regex
        )

        let service = OffsendSealService()
        let sealed = try service.seal(text: text, entities: [entity], keyData: keyData)
        XCTAssertThrowsError(try service.unseal(text: sealed.sealedText, keyData: otherKey)) { error in
            XCTAssertEqual(error as? SealError, .decryptionFailed)
        }
    }
}
