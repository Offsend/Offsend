import WorkspacePolicyCore
import XCTest
@testable import OffsendRuntime

final class OffsendProtectServiceTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("offsend-protect-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func makeService() -> OffsendProtectService {
        OffsendProtectService(configuration: .default)
    }

    private func write(_ contents: String, to relativePath: String) throws {
        let url = root.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    func testProtectCreatesIgnoreFilesAndCoversRequiredEnv() throws {
        try write("SECRET=1\n", to: ".env")

        let report = makeService().run(directoryURL: root)

        XCTAssertTrue(report.errors.isEmpty)
        // Without .offsend.yml, prepare seeds the full ignore template (covers .env*).
        XCTAssertFalse(report.prepare.createdRelativePaths.isEmpty)
        XCTAssertEqual(report.remainingRequiredCount, 0)

        let cursorignore = try String(
            contentsOf: root.appendingPathComponent(".cursorignore"),
            encoding: .utf8
        )
        XCTAssertTrue(
            cursorignore.contains(".env") || cursorignore.contains(".env*"),
            cursorignore
        )
    }

    func testProtectIgnoresExposedPemWhenIgnoreExistsWithoutPattern() throws {
        try write("# custom\n", to: ".cursorignore")
        try write("-----BEGIN CERTIFICATE-----\n", to: "server.pem")

        let report = makeService().run(directoryURL: root)

        XCTAssertTrue(report.errors.isEmpty)
        XCTAssertTrue(report.patterns.contains("*.pem"), "\(report.patterns)")
        XCTAssertEqual(report.remainingRequiredCount, 0)
        let cursorignore = try String(
            contentsOf: root.appendingPathComponent(".cursorignore"),
            encoding: .utf8
        )
        XCTAssertTrue(cursorignore.contains("*.pem"), cursorignore)
    }

    func testDryRunDoesNotWrite() throws {
        try write("SECRET=1\n", to: ".env")

        let report = makeService().run(directoryURL: root, dryRun: true)

        XCTAssertTrue(report.dryRun)
        XCTAssertFalse(report.patterns.isEmpty)
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: root.appendingPathComponent(".cursorignore").path)
        )
    }

    func testSecondRunIsIdempotent() throws {
        try write("SECRET=1\n", to: ".env")

        _ = makeService().run(directoryURL: root)
        let second = makeService().run(directoryURL: root)

        XCTAssertTrue(second.errors.isEmpty)
        XCTAssertEqual(second.remainingRequiredCount, 0)
        XCTAssertTrue(second.patterns.isEmpty || (second.ignore?.updatedRelativePaths.isEmpty ?? true))
    }

    func testPatternsToIgnoreRequiredOnlyByDefault() throws {
        try write("SECRET=1\n", to: ".env")
        try write("key\n", to: "id_rsa")

        let audit = AIWorkspacePrivacyAuditor().audit(
            directoryURL: root,
            configuration: .default
        )
        let requiredOnly = OffsendProtectService.patternsToIgnore(
            from: audit,
            includeRecommended: false
        )
        let withRecommended = OffsendProtectService.patternsToIgnore(
            from: audit,
            includeRecommended: true
        )

        XCTAssertFalse(requiredOnly.isEmpty)
        XCTAssertGreaterThanOrEqual(withRecommended.count, requiredOnly.count)
    }
}
