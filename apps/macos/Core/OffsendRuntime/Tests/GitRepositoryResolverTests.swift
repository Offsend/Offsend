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

    func testRepositoryRootRejectsMissingChildOfRepository() throws {
        let root = try makeGitRepository()
        defer { try? FileManager.default.removeItem(at: root) }

        let missing = root.appendingPathComponent("missing", isDirectory: true)
        XCTAssertThrowsError(try GitRepositoryResolver().repositoryRoot(startingAt: missing)) { error in
            guard case .notARepository(let path) = error as? GitRepositoryError else {
                return XCTFail("Expected notARepository, got \(error)")
            }
            XCTAssertEqual(path, missing.path)
        }
    }

    func testRepositoryRootAcceptsExistingFileInsideRepository() throws {
        let root = try makeGitRepository()
        defer { try? FileManager.default.removeItem(at: root) }

        let file = root.appendingPathComponent("README.md")
        try "test".write(to: file, atomically: true, encoding: .utf8)

        XCTAssertEqual(
            try GitRepositoryResolver().repositoryRoot(startingAt: file),
            root.standardizedFileURL
        )
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

    func testConfigURLFallsBackWhenGitUnavailable() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent(".git", isDirectory: true),
            withIntermediateDirectories: true
        )

        let config = GitRepositoryResolver(gitExecutable: "/nonexistent/git").configURL(in: root)

        XCTAssertEqual(
            config.standardizedFileURL.path,
            root.appendingPathComponent(".git/config").standardizedFileURL.path
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
        let fileURL = root.appendingPathComponent("nested/secrets.env")
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "STAGED_CONTENT".write(to: fileURL, atomically: true, encoding: .utf8)
        try resolver.runGit(arguments: ["add", "nested/secrets.env"], workingDirectory: root)
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
        XCTAssertEqual(try permissions(at: destination), 0o700)
        XCTAssertEqual(try permissions(at: destination.appendingPathComponent("nested")), 0o700)
        XCTAssertEqual(try permissions(at: exported[0]), 0o600)
    }

    func testExportStagedFilesRejectsUnsafeRelativePaths() throws {
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: destination) }
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

        let resolver = GitRepositoryResolver()
        XCTAssertThrowsError(
            try resolver.resolvedExportDestination(for: "../../escape.txt", in: destination)
        ) { error in
            guard case .unsafeRelativePath(let path) = error as? GitRepositoryError else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(path, "../../escape.txt")
        }

        let safe = try resolver.resolvedExportDestination(for: "src/secrets.env", in: destination)
        XCTAssertEqual(
            safe.standardizedFileURL.path,
            destination.appendingPathComponent("src/secrets.env").standardizedFileURL.path
        )
    }

    // MARK: - Subprocess-free trust-surface resolution

    /// The hook path resolves these without spawning git, so the invariant that
    /// matters is that it agrees with what git itself reports.
    func testLocalTrustSurfacesMatchGitForPlainRepository() throws {
        let root = try makeGitRepository()
        defer { try? FileManager.default.removeItem(at: root) }
        let resolver = GitRepositoryResolver()

        let surfaces = resolver.localTrustSurfaces(in: root)
        XCTAssertEqual(resolved(surfaces.config), resolved(resolver.configURL(in: root)))
        XCTAssertEqual(resolved(surfaces.hooks), resolved(resolver.hooksDirectory(in: root)))
    }

    func testLocalTrustSurfacesMatchGitForLinkedWorktree() throws {
        let root = try makeGitRepository()
        defer { try? FileManager.default.removeItem(at: root) }
        let resolver = GitRepositoryResolver()
        try resolver.runGit(
            arguments: ["commit", "--allow-empty", "-m", "base"],
            workingDirectory: root
        )
        let worktree = root.deletingLastPathComponent()
            .appendingPathComponent("worktree-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: worktree) }
        try resolver.runGit(
            arguments: ["worktree", "add", worktree.path, "-b", "side"],
            workingDirectory: root
        )

        // A linked worktree keeps config and hooks in the main repository.
        let surfaces = resolver.localTrustSurfaces(in: worktree)
        XCTAssertEqual(resolved(surfaces.config), resolved(resolver.configURL(in: worktree)))
        XCTAssertEqual(resolved(surfaces.hooks), resolved(resolver.hooksDirectory(in: worktree)))
        XCTAssertEqual(resolved(surfaces.config), resolved(resolver.configURL(in: root)))
    }

    func testLocalTrustSurfacesHonorRepositoryHooksPath() throws {
        let root = try makeGitRepository()
        defer { try? FileManager.default.removeItem(at: root) }
        let resolver = GitRepositoryResolver()
        try resolver.runGit(
            arguments: ["config", "core.hooksPath", ".githooks"],
            workingDirectory: root
        )

        let surfaces = resolver.localTrustSurfaces(in: root)
        XCTAssertEqual(resolved(surfaces.hooks), resolved(resolver.hooksDirectory(in: root)))
        XCTAssertEqual(surfaces.hooks.lastPathComponent, ".githooks")
    }

    func testLocalTrustSurfacesFollowSubmoduleGitDirectoryPointer() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let realGitDirectory = root.appendingPathComponent("modules/child", isDirectory: true)
        try FileManager.default.createDirectory(at: realGitDirectory, withIntermediateDirectories: true)
        let submodule = root.appendingPathComponent("child", isDirectory: true)
        try FileManager.default.createDirectory(at: submodule, withIntermediateDirectories: true)
        try "gitdir: ../modules/child\n"
            .write(to: submodule.appendingPathComponent(".git"), atomically: true, encoding: .utf8)

        let surfaces = GitRepositoryResolver().localTrustSurfaces(in: submodule)
        XCTAssertEqual(resolved(surfaces.config), resolved(realGitDirectory.appendingPathComponent("config")))
        XCTAssertEqual(resolved(surfaces.hooks), resolved(realGitDirectory.appendingPathComponent("hooks")))
    }

    func testLocalTrustSurfacesFallBackWithoutGitDirectory() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let surfaces = GitRepositoryResolver().localTrustSurfaces(in: root)
        XCTAssertEqual(resolved(surfaces.config), resolved(root.appendingPathComponent(".git/config")))
        XCTAssertEqual(resolved(surfaces.hooks), resolved(root.appendingPathComponent(".git/hooks")))
    }

    private func resolved(_ url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path
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

    private func permissions(at url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes[.posixPermissions] as? NSNumber)?.intValue ?? -1
    }
}
