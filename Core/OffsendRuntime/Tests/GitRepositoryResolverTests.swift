import XCTest
@testable import OffsendRuntime

final class GitRepositoryResolverTests: XCTestCase {
    func testRepositoryRootFindsGitDirectory() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent(".git", isDirectory: true),
            withIntermediateDirectories: true
        )
        let nested = root.appendingPathComponent("src/nested", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)

        let resolver = GitRepositoryResolver()
        let discovered = try resolver.repositoryRoot(startingAt: nested)
        XCTAssertEqual(discovered.standardizedFileURL, root.standardizedFileURL)
    }

    func testRepositoryRootThrowsForNonRepository() {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let resolver = GitRepositoryResolver()

        XCTAssertThrowsError(try resolver.repositoryRoot(startingAt: root)) { error in
            guard case .notARepository = error as? GitRepositoryError else {
                return XCTFail("Expected notARepository, got \(error)")
            }
        }
    }

    func testHooksDirectoryFallsBackWhenGitUnavailable() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try FileManager.default.createDirectory(
            at: root.appendingPathComponent(".git", isDirectory: true),
            withIntermediateDirectories: true
        )

        let resolver = GitRepositoryResolver(gitExecutable: "/nonexistent/git")
        let hooks = resolver.hooksDirectory(in: root)
        XCTAssertEqual(
            hooks.standardizedFileURL.path,
            root.appendingPathComponent(".git/hooks").standardizedFileURL.path
        )
    }

    func testHooksDirectoryHonorsCoreHooksPath() throws {
        let root = try makeGitRepository()
        defer { try? FileManager.default.removeItem(at: root) }

        let resolver = GitRepositoryResolver()
        try resolver.runGit(arguments: ["config", "core.hooksPath", "custom-hooks"], workingDirectory: root)

        let hooks = resolver.hooksDirectory(in: root)
        XCTAssertEqual(
            hooks.standardizedFileURL.path,
            root.appendingPathComponent("custom-hooks").standardizedFileURL.path
        )
    }

    func testExportStagedFilesUsesIndexContentNotWorkingTree() throws {
        let root = try makeGitRepository()
        defer { try? FileManager.default.removeItem(at: root) }

        let resolver = GitRepositoryResolver()
        let fileURL = root.appendingPathComponent("secrets.env")
        try "STAGED_CONTENT".write(to: fileURL, atomically: true, encoding: .utf8)
        try resolver.runGit(arguments: ["add", "secrets.env"], workingDirectory: root)
        // Modify the working tree after staging; the staged blob must win.
        try "WORKING_TREE_CONTENT".write(to: fileURL, atomically: true, encoding: .utf8)

        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: destination) }

        let exported = try resolver.exportStagedFiles(in: root, to: destination)
        XCTAssertEqual(exported.count, 1)
        XCTAssertEqual(exported[0].lastPathComponent, "secrets.env")
        XCTAssertEqual(
            try String(contentsOf: exported[0], encoding: .utf8),
            "STAGED_CONTENT"
        )
    }

    private func makeGitRepository() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let resolver = GitRepositoryResolver()
        try resolver.runGit(arguments: ["init"], workingDirectory: root)
        try resolver.runGit(arguments: ["config", "user.email", "test@example.com"], workingDirectory: root)
        try resolver.runGit(arguments: ["config", "user.name", "Offsend Tests"], workingDirectory: root)
        return root
    }
}
