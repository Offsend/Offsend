import DetectionCore
import XCTest
@testable import OffsendRuntime

final class OffsendHistoryServiceTests: XCTestCase {
    // Realistic AKIA-shaped key; doc sample EXAMPLE keys are filtered by detectors.
    private let secret = "AKIA1234567890ABCDEF"
    private var context: OffsendRuntimeContext {
        OffsendRuntimeContext(settings: .default, customDictionaries: [])
    }

    func testRedactReplacesSecretSpans() {
        // Build a synthetic entity range over a known substring.
        let text = "token=sk-abcdefghijklmnopqrstuvwxyz123456 before"
        let value = "sk-abcdefghijklmnopqrstuvwxyz123456"
        guard let range = text.range(of: value) else {
            XCTFail("range")
            return
        }
        let entity = SensitiveEntity(
            type: .openAIAPIKey,
            range: range,
            value: value,
            confidence: 1.0,
            source: .secret
        )
        let (scrubbed, count) = OffsendHistoryService.redact(text: text, entities: [entity])
        XCTAssertEqual(count, 1)
        XCTAssertTrue(scrubbed.contains("OFFSEND_REDACTED_openAIAPIKey"))
        XCTAssertFalse(scrubbed.contains(value))
    }

    func testDiscoversAuditsAndScrubsPlantedTranscript() async throws {
        let root = try makeTempRoot(prefix: "offsend-hist")
        let home = root.appendingPathComponent("home", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let transcripts = try makeCursorTranscriptsDir(projectRoot: root, home: home)
        let fileURL = transcripts.appendingPathComponent("session-1.jsonl")
        let jsonl = #"{"role":"user","content":"AWS_ACCESS_KEY_ID=\#(secret)"}"# + "\n"
        try jsonl.write(to: fileURL, atomically: true, encoding: .utf8)

        let report = await OffsendHistoryService().audit(
            projectRoot: root,
            homeDirectory: home,
            context: context,
            allProjects: false
        )
        XCTAssertEqual(report.filesScanned, 1)
        XCTAssertTrue(report.hasFindings)
        XCTAssertFalse(report.findings[0].secretTypes.isEmpty)

        let scrub = await OffsendHistoryService().scrub(
            projectRoot: root,
            homeDirectory: home,
            context: context,
            apply: true,
            allProjects: false
        )
        XCTAssertGreaterThan(scrub.redactionCount, 0)
        // Enumerator may resolve /var → /private/var; compare resolved paths.
        XCTAssertEqual(
            scrub.filesTouched.map(resolvedPath),
            [resolvedPath(fileURL.path)]
        )
        XCTAssertTrue(scrub.errors.isEmpty)
        let after = try String(contentsOf: fileURL, encoding: .utf8)
        XCTAssertTrue(after.contains("OFFSEND_REDACTED_"))
        XCTAssertFalse(after.contains(secret))
    }

    func testScrubApplySkipsFilesLargerThanScanLimit() async throws {
        let root = try makeTempRoot(prefix: "offsend-hist-big")
        let home = root.appendingPathComponent("home", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let transcripts = try makeCursorTranscriptsDir(projectRoot: root, home: home)
        let fileURL = transcripts.appendingPathComponent("session-1.jsonl")
        // Secret near the start so the bounded prefix scan still finds it,
        // then padding past the limit; the tail must never be overwritten.
        let padding = String(repeating: "x", count: OffsendHistoryService.maxFileBytes)
        let content = #"{"role":"user","content":"AWS_ACCESS_KEY_ID=\#(secret) \#(padding) TAIL-MARKER"}"# + "\n"
        try content.write(to: fileURL, atomically: true, encoding: .utf8)

        let audit = await OffsendHistoryService().audit(
            projectRoot: root,
            homeDirectory: home,
            context: context,
            allProjects: false
        )
        XCTAssertTrue(audit.hasFindings)

        let scrub = await OffsendHistoryService().scrub(
            projectRoot: root,
            homeDirectory: home,
            context: context,
            apply: true,
            allProjects: false
        )
        XCTAssertTrue(scrub.filesTouched.isEmpty)
        XCTAssertEqual(scrub.redactionCount, 0)
        XCTAssertEqual(scrub.errors.count, 1)
        XCTAssertTrue(scrub.errors[0].contains("skipped scrub"))

        let after = try String(contentsOf: fileURL, encoding: .utf8)
        XCTAssertEqual(after, content, "file larger than the scan limit must not be rewritten")
        XCTAssertTrue(after.contains("TAIL-MARKER"))
    }

    func testClaudeTranscriptFilterMatchesExactProjectDirOnly() async throws {
        let root = try makeTempRoot(prefix: "offsend-hist-claude")
        // Project root deliberately named `app` to check `my-app` is not picked up.
        let projectRoot = root.appendingPathComponent("app", isDirectory: true)
        let home = root.appendingPathComponent("home", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)

        let claudeProjects = home.appendingPathComponent(".claude/projects")
        let matching = claudeProjects.appendingPathComponent(
            OffsendHistoryService.claudeProjectDirName(for: projectRoot)
        )
        let other = claudeProjects.appendingPathComponent(
            OffsendHistoryService.claudeProjectDirName(for: root.appendingPathComponent("my-app"))
        )
        try FileManager.default.createDirectory(at: matching, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        let jsonl = #"{"role":"user","content":"AWS_ACCESS_KEY_ID=\#(secret)"}"# + "\n"
        try jsonl.write(to: matching.appendingPathComponent("s.jsonl"), atomically: true, encoding: .utf8)
        try jsonl.write(to: other.appendingPathComponent("s.jsonl"), atomically: true, encoding: .utf8)

        let report = await OffsendHistoryService().audit(
            projectRoot: projectRoot,
            homeDirectory: home,
            context: context,
            allProjects: false
        )
        XCTAssertEqual(report.filesScanned, 1)
        XCTAssertEqual(report.findings.count, 1)
        XCTAssertTrue(resolvedPath(report.findings[0].path).hasPrefix(resolvedPath(matching.path)))
    }

    func testAuditJSONSchemaIsStableForScripts() async throws {
        let root = try makeTempRoot(prefix: "offsend-hist-json")
        let home = root.appendingPathComponent("home", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let transcripts = try makeCursorTranscriptsDir(projectRoot: root, home: home)
        let fileURL = transcripts.appendingPathComponent("session-1.jsonl")
        let jsonl = #"{"role":"user","content":"AWS_ACCESS_KEY_ID=\#(secret)"}"# + "\n"
        try jsonl.write(to: fileURL, atomically: true, encoding: .utf8)

        let report = await OffsendHistoryService().audit(
            projectRoot: root,
            homeDirectory: home,
            context: context,
            allProjects: false
        )
        let json = OffsendHistoryReporter.renderAudit(report, format: .json)
        let data = try XCTUnwrap(json.data(using: .utf8))
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )

        XCTAssertEqual(object["schemaVersion"] as? Int, OffsendHistoryReporter.jsonSchemaVersion)
        XCTAssertEqual(object["filesScanned"] as? Int, 1)
        XCTAssertEqual(object["hasFindings"] as? Bool, true)
        XCTAssertEqual(object["filesWithFindings"] as? Int, 1)
        XCTAssertNotNil(object["findings"] as? [[String: Any]])
        XCTAssertNotNil(object["errors"] as? [Any])

        let empty = OffsendHistoryReporter.renderAudit(
            OffsendHistoryAuditReport(filesScanned: 0, findings: [], errors: []),
            format: .json
        )
        let emptyObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(empty.utf8)) as? [String: Any]
        )
        XCTAssertEqual(emptyObject["schemaVersion"] as? Int, 1)
        XCTAssertEqual(emptyObject["hasFindings"] as? Bool, false)
    }

    func testScrubJSONIncludesSchemaVersion() throws {
        let report = OffsendHistoryScrubReport(
            dryRun: true,
            filesTouched: ["/tmp/a.jsonl"],
            redactionCount: 2,
            findings: [
                OffsendHistoryFinding(
                    path: "/tmp/a.jsonl",
                    source: "cursor",
                    secretTypes: ["awsAccessKeyId"],
                    findingCount: 2
                )
            ]
        )
        let json = OffsendHistoryReporter.renderScrub(report, format: .json)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any]
        )
        XCTAssertEqual(object["schemaVersion"] as? Int, 1)
        XCTAssertEqual(object["dryRun"] as? Bool, true)
        XCTAssertEqual(object["hasFindings"] as? Bool, true)
        XCTAssertEqual(object["redactionCount"] as? Int, 2)
    }

    func testCursorProjectSlug() {
        let url = URL(fileURLWithPath: "/Users/me/Projects/app")
        XCTAssertEqual(
            OffsendHistoryService.cursorProjectSlug(for: url),
            "Users-me-Projects-app"
        )
    }

    func testClaudeProjectDirName() {
        let url = URL(fileURLWithPath: "/Users/me/Projects/my.app")
        XCTAssertEqual(
            OffsendHistoryService.claudeProjectDirName(for: url),
            "-Users-me-Projects-my-app"
        )
    }

    // MARK: - Helpers

    private func resolvedPath(_ path: String) -> String {
        URL(fileURLWithPath: path).resolvingSymlinksInPath().path
    }

    private func makeTempRoot(prefix: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func makeCursorTranscriptsDir(projectRoot: URL, home: URL) throws -> URL {
        let slug = OffsendHistoryService.cursorProjectSlug(for: projectRoot)
        let transcripts = home
            .appendingPathComponent(".cursor/projects")
            .appendingPathComponent(slug)
            .appendingPathComponent("agent-transcripts")
            .appendingPathComponent("session-1")
        try FileManager.default.createDirectory(at: transcripts, withIntermediateDirectories: true)
        return transcripts
    }
}
