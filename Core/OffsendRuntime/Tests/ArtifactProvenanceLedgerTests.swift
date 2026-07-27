import Dispatch
import XCTest
@testable import OffsendRuntime

final class ArtifactProvenanceLedgerTests: XCTestCase {
    private var root: URL!
    private var logURL: URL!
    private var ledger: ArtifactProvenanceLedger!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent(".git/hooks", isDirectory: true),
            withIntermediateDirectories: true
        )
        logURL = root.appendingPathComponent("store/artifact-provenance.jsonl")
        ledger = ArtifactProvenanceLedger(logURL: logURL)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testRecordsMetadataWithoutAbsoluteRepositoryPathOrContent() throws {
        let config = root.appendingPathComponent(".cursor/hooks.json")
        try FileManager.default.createDirectory(
            at: config.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try #"{"command":"private-command-value"}"#.write(
            to: config,
            atomically: true,
            encoding: .utf8
        )
        let classifier = ExecutableArtifactClassifier(
            projectRoot: root,
            gitResolver: GitRepositoryResolver(gitExecutable: "/nonexistent/git")
        )

        let entry = try XCTUnwrap(
            ledger.record(
                path: config.path,
                projectRoot: root,
                adapter: .cursor,
                toolName: "Write",
                classifier: classifier,
                now: Date(timeIntervalSince1970: 1_700_000_000)
            )
        )

        XCTAssertEqual(entry.relativePath, ".cursor/hooks.json")
        XCTAssertEqual(entry.artifactKind, .editorHookConfig)
        XCTAssertNotNil(entry.contentHash)
        let raw = try String(contentsOf: logURL, encoding: .utf8)
        XCTAssertFalse(raw.contains(root.path))
        XCTAssertFalse(raw.contains("private-command-value"))
        let permissions = try FileManager.default.attributesOfItem(atPath: logURL.path)
        XCTAssertEqual((permissions[.posixPermissions] as? NSNumber)?.intValue, 0o600)
    }

    func testIgnoresOrdinarySourceFiles() throws {
        let source = root.appendingPathComponent("App.swift")
        try "print(1)".write(to: source, atomically: true, encoding: .utf8)

        XCTAssertNil(
            ledger.record(
                path: source.path,
                projectRoot: root,
                adapter: .claude,
                toolName: "Write",
                classifier: ExecutableArtifactClassifier(
                    projectRoot: root,
                    gitResolver: GitRepositoryResolver(gitExecutable: "/nonexistent/git")
                )
            )
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: logURL.path))
    }

    func testRecentEntriesFiltersRepositoryAndAge() throws {
        let config = root.appendingPathComponent(".vscode/tasks.json")
        try FileManager.default.createDirectory(
            at: config.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "{}".write(to: config, atomically: true, encoding: .utf8)
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        _ = ledger.record(
            path: config.path,
            projectRoot: root,
            adapter: .cursor,
            toolName: "Edit",
            classifier: ExecutableArtifactClassifier(
                projectRoot: root,
                gitResolver: GitRepositoryResolver(gitExecutable: "/nonexistent/git")
            ),
            now: now
        )

        XCTAssertEqual(ledger.recentEntries(repositoryRoot: root, since: now.addingTimeInterval(-1)).count, 1)
        XCTAssertTrue(ledger.recentEntries(repositoryRoot: root, since: now.addingTimeInterval(1)).isEmpty)
        XCTAssertTrue(
            ledger.recentEntries(
                repositoryRoot: root.appendingPathComponent("other"),
                since: now.addingTimeInterval(-1)
            ).isEmpty
        )
    }

    func testChainLinksEachEntryToThePreviousLine() throws {
        try recordThreeEntries()

        let entries = ledger.recentEntries(repositoryRoot: root, since: .distantPast)
        XCTAssertEqual(entries.count, 3)
        XCTAssertNil(entries[0].previousHash)
        XCTAssertNotNil(entries[1].previousHash)
        XCTAssertNotEqual(entries[1].previousHash, entries[2].previousHash)
        XCTAssertEqual(ledger.verifyChain(), .intact)
    }

    func testChainDetectsRemovedEntry() throws {
        try recordThreeEntries()
        var lines = try String(contentsOf: logURL, encoding: .utf8)
            .split(separator: "\n").map(String.init)
        lines.remove(at: 1)
        try lines.joined(separator: "\n").appending("\n")
            .write(to: logURL, atomically: true, encoding: .utf8)

        XCTAssertEqual(ledger.verifyChain(), .broken(line: 2))
    }

    func testChainDetectsRewrittenEntry() throws {
        try recordThreeEntries()
        let raw = try String(contentsOf: logURL, encoding: .utf8)
        try raw.replacingOccurrences(of: "\"toolName\":\"Edit0\"", with: "\"toolName\":\"Edit9\"")
            .write(to: logURL, atomically: true, encoding: .utf8)

        XCTAssertEqual(ledger.verifyChain(), .broken(line: 2))
    }

    func testChainDetectsEntriesCutFromTheEnd() throws {
        try recordThreeEntries()
        try writeLines(dropping: 2)

        XCTAssertEqual(ledger.verifyChain(), .truncated(expected: 3, found: 2))
    }

    func testChainDetectsEntriesCutFromTheStart() throws {
        try recordThreeEntries()
        try writeLines(dropping: 0)

        XCTAssertEqual(ledger.verifyChain(), .truncated(expected: 3, found: 2))
    }

    func testChainDetectsRewrittenLastEntry() throws {
        try recordThreeEntries()
        var lines = try logLines()
        lines[lines.count - 1] = "{not json"
        try write(lines)

        XCTAssertEqual(ledger.verifyChain(), .broken(line: 3))
    }

    /// Ledgers written before the anchor existed must not read as truncated.
    func testChainWithoutAnchorFallsBackToTheInFileChain() throws {
        try recordThreeEntries()
        try FileManager.default.removeItem(at: logURL.appendingPathExtension("anchor"))

        XCTAssertEqual(ledger.verifyChain(), .intact)
    }

    func testChainIsUnverifiableWithoutChainedEntries() throws {
        XCTAssertEqual(ledger.verifyChain(), .unverifiable)
    }

    /// A multi-file edit fires one post-write hook per file. Unserialized, they
    /// read the same chain head and the log looks tampered with afterwards.
    func testConcurrentRecordsDoNotBreakTheChain() throws {
        let ledger = try XCTUnwrap(self.ledger)
        let root = try XCTUnwrap(self.root)
        let config = root.appendingPathComponent(".vscode/tasks.json")
        try FileManager.default.createDirectory(
            at: config.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "{}".write(to: config, atomically: true, encoding: .utf8)
        let classifier = ExecutableArtifactClassifier(
            projectRoot: root,
            gitResolver: GitRepositoryResolver(gitExecutable: "/nonexistent/git")
        )
        // Seeded so the concurrent writers race over an existing chain head
        // rather than an empty log, which is what a real ledger looks like.
        _ = ledger.record(
            path: config.path,
            projectRoot: root,
            adapter: .cursor,
            toolName: "Seed",
            classifier: classifier
        )

        DispatchQueue.concurrentPerform(iterations: 8) { index in
            _ = ledger.record(
                path: config.path,
                projectRoot: root,
                adapter: .cursor,
                toolName: "Edit\(index)",
                classifier: classifier
            )
        }

        XCTAssertEqual(ledger.recentEntries(repositoryRoot: root, since: .distantPast).count, 9)
        XCTAssertEqual(ledger.verifyChain(), .intact)
    }

    private func logLines() throws -> [String] {
        try String(contentsOf: logURL, encoding: .utf8)
            .split(separator: "\n").map(String.init)
    }

    private func write(_ lines: [String]) throws {
        try lines.joined(separator: "\n").appending("\n")
            .write(to: logURL, atomically: true, encoding: .utf8)
    }

    private func writeLines(dropping index: Int) throws {
        var lines = try logLines()
        lines.remove(at: index)
        try write(lines)
    }

    private func recordThreeEntries() throws {
        let config = root.appendingPathComponent(".vscode/tasks.json")
        try FileManager.default.createDirectory(
            at: config.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "{}".write(to: config, atomically: true, encoding: .utf8)
        let classifier = ExecutableArtifactClassifier(
            projectRoot: root,
            gitResolver: GitRepositoryResolver(gitExecutable: "/nonexistent/git")
        )
        for index in 0..<3 {
            _ = ledger.record(
                path: config.path,
                projectRoot: root,
                adapter: .cursor,
                toolName: "Edit\(index)",
                classifier: classifier,
                now: Date(timeIntervalSince1970: 1_700_000_000 + Double(index))
            )
        }
    }
}
