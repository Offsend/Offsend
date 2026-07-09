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

    func testRejectsBothKeyAndKeyFile() {
        XCTAssertThrowsError(
            try SealKeyResolver.resolve(key: "abc", keyFilePath: "/tmp/k", environment: [:])
        ) { error in
            guard case SealError.invalidKey(let reason) = error else {
                return XCTFail("Expected invalidKey, got \(error)")
            }
            XCTAssertTrue(reason.contains("not both"))
        }
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
        XCTAssertThrowsError(
            try SealKeyResolver.resolve(key: nil, keyFilePath: nil, environment: [:])
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
        XCTAssertThrowsError(
            try SealKeyResolver.resolve(
                key: nil,
                keyFilePath: nil,
                environment: [SealKeyResolver.environmentVariable: ""]
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
