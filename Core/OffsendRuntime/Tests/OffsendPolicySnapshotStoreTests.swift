import XCTest
@testable import OffsendRuntime

final class OffsendPolicySnapshotStoreTests: XCTestCase {
    private var root: URL!
    private var storage: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("offsend-policy-repo-\(UUID().uuidString)", isDirectory: true)
        storage = FileManager.default.temporaryDirectory
            .appendingPathComponent("offsend-policy-store-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
        try? FileManager.default.removeItem(at: storage)
    }

    func testTrustAndDetectDrift() throws {
        try writePolicy("version: 1\n")
        let store = OffsendPolicySnapshotStore(storageRoot: storage)
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        let snapshot = try store.trust(directory: root, now: now)
        XCTAssertEqual(snapshot.repositoryPath, root.standardizedFileURL.path)
        XCTAssertEqual(snapshot.trustedAt, now)
        XCTAssertTrue(store.status(directory: root).isTrusted)

        try writePolicy("version: 1\ncheck:\n  fail_on: warn\n")
        guard case .drift(let trusted, let reason) = store.status(directory: root) else {
            return XCTFail("Expected policy drift")
        }
        XCTAssertEqual(trusted.configHash, snapshot.configHash)
        XCTAssertTrue(reason.contains("changed"))
    }

    func testMissingPolicyAfterTrustIsDrift() throws {
        try writePolicy("version: 1\n")
        let store = OffsendPolicySnapshotStore(storageRoot: storage)
        _ = try store.trust(directory: root)
        try FileManager.default.removeItem(at: root.appendingPathComponent(ProjectConfigLoader.filename))

        guard case .drift(_, let reason) = store.status(directory: root) else {
            return XCTFail("Expected missing policy to drift")
        }
        XCTAssertTrue(reason.contains("missing"))
    }

    func testTrustRejectsInvalidPolicy() throws {
        try writePolicy("not: [valid")
        let store = OffsendPolicySnapshotStore(storageRoot: storage)

        XCTAssertThrowsError(try store.trust(directory: root)) { error in
            guard case .configInvalid = error as? OffsendPolicySnapshotError else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
        XCTAssertEqual(store.status(directory: root), .missing)
    }

    func testRemoveReturnsToMissing() throws {
        try writePolicy("version: 1\n")
        let store = OffsendPolicySnapshotStore(storageRoot: storage)
        _ = try store.trust(directory: root)

        try store.remove(directory: root)
        XCTAssertEqual(store.status(directory: root), .missing)
    }

    private func writePolicy(_ yaml: String) throws {
        try yaml.write(
            to: root.appendingPathComponent(ProjectConfigLoader.filename),
            atomically: true,
            encoding: .utf8
        )
    }
}
