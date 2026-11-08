#if canImport(Security)
import DetectionCore
import Foundation
import MaskingCore
import XCTest
@testable import StorageCore

final class SecureLocalStoreSensitiveTermTests: XCTestCase {
    private var temporaryDirectory: URL!
    private let keyA = Data(repeating: 0x11, count: 32)
    private let keyB = Data(repeating: 0x22, count: 32)

    override func setUpWithError() throws {
        try super.setUpWithError()
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("secure-local-store-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: temporaryDirectory)
        try super.tearDownWithError()
    }

    func testSensitiveTermIsSealedOnDiskAndRoundTrips() throws {
        try setEncryptSensitiveTerms(true)
        let store = try makeStore(key: keyA)
        let secret = "TesztSzo98765"
        let items = [
            CustomDictionaryItem(kind: .client, value: "Acme Corp"),
            CustomDictionaryItem(kind: .sensitiveTerm, value: secret),
            CustomDictionaryItem(kind: .regex, value: "SECRET_[0-9]+")
        ]

        try store.saveCustomDictionaries(items)

        let raw = try dictionaryFileText()
        XCTAssertFalse(raw.contains(secret))
        XCTAssertTrue(raw.contains("Acme Corp"))
        XCTAssertTrue(raw.contains("SECRET_[0-9]+"))
        XCTAssertTrue(raw.contains("\"valueSealed\":true"))

        let loaded = try store.loadCustomDictionaries()
        XCTAssertEqual(loaded.map(\.id), items.map(\.id))
        XCTAssertEqual(loaded.map(\.kind), items.map(\.kind))
        XCTAssertEqual(loaded.map(\.value), items.map(\.value))

        try FileManager.default.setAttributes([.posixPermissions: 0o444], ofItemAtPath: dictionaryFileURL.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: dictionaryFileURL.path)
        }
        XCTAssertEqual(try store.loadCustomDictionaries().map(\.value), items.map(\.value))
    }

    func testLegacyPlaintextSensitiveTermStaysPlaintextWhenEncryptionIsOff() throws {
        let secret = "legacy-secret"
        let item = CustomDictionaryItem(kind: .sensitiveTerm, value: secret)
        try LocalStoreJSONCodec().save([item], to: dictionaryFileURL)
        XCTAssertTrue(try dictionaryFileText().contains(secret))

        let store = try makeStore(key: keyA)
        let loaded = try store.loadCustomDictionaries()
        XCTAssertEqual(loaded.map(\.id), [item.id])
        XCTAssertEqual(loaded.map(\.value), [secret])

        let raw = try dictionaryFileText()
        XCTAssertTrue(raw.contains(secret))
        XCTAssertFalse(raw.contains("valueSealed"))
    }

    func testEnablingEncryptionSealsExistingSensitiveTermsAndDisablingRestoresPlaintext() throws {
        let store = try makeStore(key: keyA)
        let secret = "TesztSzo98765"
        try store.saveCustomDictionaries([
            CustomDictionaryItem(kind: .client, value: "Acme Corp"),
            CustomDictionaryItem(kind: .sensitiveTerm, value: secret)
        ])
        XCTAssertTrue(try dictionaryFileText().contains(secret))
        XCTAssertFalse(try dictionaryFileText().contains("valueSealed"))

        try setEncryptSensitiveTerms(true)
        var raw = try dictionaryFileText()
        XCTAssertFalse(raw.contains(secret))
        XCTAssertTrue(raw.contains("Acme Corp"))
        XCTAssertTrue(raw.contains("\"valueSealed\":true"))
        XCTAssertEqual(try store.loadCustomDictionaries().map(\.value).sorted(), ["Acme Corp", secret].sorted())

        try setEncryptSensitiveTerms(false)
        raw = try dictionaryFileText()
        XCTAssertTrue(raw.contains(secret))
        XCTAssertTrue(raw.contains("Acme Corp"))
        XCTAssertFalse(raw.contains("valueSealed"))
        XCTAssertEqual(try store.loadCustomDictionaries().map(\.value).sorted(), ["Acme Corp", secret].sorted())
    }

    func testOtherKindsStayPlaintext() throws {
        try setEncryptSensitiveTerms(true)
        let store = try makeStore(key: keyA)
        try store.saveCustomDictionaries([
            CustomDictionaryItem(kind: .client, value: "Acme Corp"),
            CustomDictionaryItem(kind: .company, value: "Offsend"),
            CustomDictionaryItem(kind: .project, value: "Codename"),
            CustomDictionaryItem(kind: .internalDomain, value: "intra.example"),
            CustomDictionaryItem(kind: .regex, value: "SECRET_[0-9]+")
        ])

        let raw = try dictionaryFileText()
        XCTAssertFalse(raw.contains("valueSealed"))
        XCTAssertTrue(raw.contains("Acme Corp"))
        XCTAssertTrue(raw.contains("Offsend"))
        XCTAssertTrue(raw.contains("Codename"))
        XCTAssertTrue(raw.contains("intra.example"))
        XCTAssertTrue(raw.contains("SECRET_[0-9]+"))
    }

    func testSealedSensitiveTermDoesNotOpenWithAnotherKey() throws {
        try setEncryptSensitiveTerms(true)
        let store = try makeStore(key: keyA)
        try store.saveCustomDictionaries([
            CustomDictionaryItem(kind: .sensitiveTerm, value: "hidden")
        ])

        let other = try makeStore(key: keyB)
        XCTAssertThrowsError(try other.loadCustomDictionaries()) { error in
            guard let storageError = error as? StorageError,
                  case .sensitiveTermProtectionFailed = storageError else {
                return XCTFail("unexpected error: \(error)")
            }
        }
    }

    func testTamperedSensitiveTermFailsToLoad() throws {
        try setEncryptSensitiveTerms(true)
        let store = try makeStore(key: keyA)
        try store.saveCustomDictionaries([
            CustomDictionaryItem(kind: .sensitiveTerm, value: "hidden")
        ])

        let data = try Data(contentsOf: dictionaryFileURL)
        var rows = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        var sealed = try XCTUnwrap(rows[0]["value"] as? String)
        let replacement: Character = sealed.first == "A" ? "B" : "A"
        sealed.replaceSubrange(sealed.startIndex...sealed.startIndex, with: String(replacement))
        rows[0]["value"] = sealed
        try JSONSerialization.data(withJSONObject: rows).write(to: dictionaryFileURL)

        XCTAssertThrowsError(try store.loadCustomDictionaries()) { error in
            guard let storageError = error as? StorageError,
                  case .sensitiveTermProtectionFailed = storageError else {
                return XCTFail("unexpected error: \(error)")
            }
        }
    }

    func testMissingDictionaryFileLoadsEmpty() throws {
        let store = try makeStore(key: keyA)
        XCTAssertEqual(try store.loadCustomDictionaries(), [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: dictionaryFileURL.path))
    }

    private func setEncryptSensitiveTerms(_ enabled: Bool) throws {
        let store = try makeStore(key: keyA)
        var settings = try store.loadSettings()
        settings.encryptSensitiveTerms = enabled
        try store.saveSettings(settings)
    }

    private func makeStore(key: Data) throws -> SecureLocalStore {
        try SecureLocalStore(directory: temporaryDirectory, masterKey: key, maskingEngine: PassthroughTextMasking())
    }

    private var dictionaryFileURL: URL {
        temporaryDirectory.appendingPathComponent("custom_dictionaries.json")
    }

    private func dictionaryFileText() throws -> String {
        try String(contentsOf: dictionaryFileURL, encoding: .utf8)
    }
}

private struct PassthroughTextMasking: TextMasking {
    func mask(text: String, entities: [SensitiveEntity], ttl: MappingTTL) -> MaskingResult {
        MaskingResult(maskedText: text, mapping: [:], retention: .ephemeral)
    }

    func restore(text: String, mapping: [String: String]) -> String {
        mapping.reduce(text) { $0.replacingOccurrences(of: $1.key, with: $1.value) }
    }
}
#endif
