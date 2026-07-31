import XCTest
@testable import StorageCore

final class SealKeyStoreTests: XCTestCase {
    func testInMemoryRoundTrip() throws {
        let store = InMemorySealKeyStore()
        XCTAssertFalse(store.hasKey)

        let key = Data((0..<32).map { UInt8($0) })
        try store.saveKey(key)
        XCTAssertTrue(store.hasKey)
        XCTAssertEqual(try store.loadKey(), key)

        try store.deleteKey()
        XCTAssertFalse(store.hasKey)
        XCTAssertNil(try store.loadKey())
    }

    func testInMemoryRejectsWrongLength() {
        let store = InMemorySealKeyStore()
        XCTAssertThrowsError(try store.saveKey(Data([1, 2, 3]))) { error in
            XCTAssertEqual(error as? SealKeyStoreError, .invalidKeyLength(3))
        }
    }
}
