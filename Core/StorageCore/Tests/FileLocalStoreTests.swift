import DetectionCore
import Foundation
import MaskingCore
import XCTest
@testable import StorageCore

final class FileLocalStoreTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("file-local-store-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: temporaryDirectory)
        try super.tearDownWithError()
    }

    func testLoadSettingsReturnsDefaultWhenMissing() throws {
        let store = try FileLocalStore(directory: temporaryDirectory)
        XCTAssertEqual(try store.loadSettings(), .default)
    }

    func testSaveAndLoadSettings() throws {
        let store = try FileLocalStore(directory: temporaryDirectory)
        var settings = AppSettings.default
        settings.protectionEnabled = false
        settings.enabledDetectors = [.openAIAPIKey, .githubToken]

        try store.saveSettings(settings)
        XCTAssertEqual(try store.loadSettings(), settings)
    }

    func testSaveAndLoadCustomDictionaries() throws {
        let store = try FileLocalStore(directory: temporaryDirectory)
        let dictionaries = [
            CustomDictionaryItem(kind: .client, value: "Acme Corp"),
            CustomDictionaryItem(kind: .regex, value: "SECRET_[0-9]+")
        ]

        try store.saveCustomDictionaries(dictionaries)
        let loaded = try store.loadCustomDictionaries()
        XCTAssertEqual(loaded.map(\.kind), dictionaries.map(\.kind))
        XCTAssertEqual(loaded.map(\.value), dictionaries.map(\.value))
    }

    func testMappingMethodsAreNoOps() throws {
        let store = try FileLocalStore(directory: temporaryDirectory)
        let mapping = MaskingResult(
            maskedText: "token=[REDACTED]",
            mapping: ["[REDACTED]": "sk-secret"],
            retention: .expiring(Date().addingTimeInterval(3_600))
        )

        try store.saveMapping(mapping)
        XCTAssertNil(try store.restore(text: "token=[REDACTED]"))
        XCTAssertTrue(try store.mappingSummaries().isEmpty)
        try store.deleteMapping(id: mapping.id)
        try store.clearMappings()
        try store.cleanupExpiredMappings()
    }

    func testSaveAndLoadLicenseState() throws {
        let store = try FileLocalStore(directory: temporaryDirectory)
        var state = LicenseState()
        state.plan = .pro

        try store.saveLicenseState(state)
        XCTAssertEqual(try store.loadLicenseState(), state)
    }

    func testLocalStoreFactoryUsesFileStoreOnLinux() throws {
        #if os(Linux)
        let store = try LocalStoreFactory.makeDefaultStore()
        XCTAssertTrue(store is FileLocalStore)
        #else
        let store = try LocalStoreFactory.makeDefaultStore()
        XCTAssertTrue(store is SecureLocalStore)
        #endif
    }
}

final class LocalStoreDirectoryTests: XCTestCase {
    func testDefaultURLUsesApplicationSupportOnApplePlatforms() {
        #if !os(Linux)
        let url = LocalStoreDirectory.defaultURL()
        XCTAssertTrue(url.path.contains("Offsend"))
        #endif
    }

    func testDefaultURLUsesXDGConfigHomeOnLinux() {
        #if os(Linux)
        let fileManager = FileManager.default
        let base = fileManager.temporaryDirectory.appendingPathComponent("xdg-\(UUID().uuidString)", isDirectory: true)
        setenv("XDG_CONFIG_HOME", base.path, 1)
        defer { unsetenv("XDG_CONFIG_HOME") }

        let url = LocalStoreDirectory.defaultURL(fileManager: fileManager)
        XCTAssertEqual(url.path, base.appendingPathComponent("offsend", isDirectory: true).path)
        #endif
    }
}
