import XCTest
@testable import OffsendScanAPI

final class RepositoryURLValidatorTests: XCTestCase {
    // MARK: - Valid URLs

    func testNormalizesHTTPSGitHubURL() throws {
        let url = try RepositoryURLValidator.normalize("https://github.com/offsend/macos")
        XCTAssertEqual(url.absoluteString, "https://github.com/offsend/macos")
    }

    func testNormalizesSSHGitHubURL() throws {
        let url = try RepositoryURLValidator.normalize("git@github.com:offsend/macos.git")
        XCTAssertEqual(url.host, "github.com")
        XCTAssertEqual(url.path, "/offsend/macos")
    }

    func testNormalizesGitHubURLWithGitSuffix() throws {
        let url = try RepositoryURLValidator.normalize("https://github.com/org/repo.git")
        XCTAssertEqual(url.path, "/org/repo")
    }

    func testNormalizesGitHubURLWithTrailingSlash() throws {
        let url = try RepositoryURLValidator.normalize("https://github.com/org/repo/")
        XCTAssertEqual(url.path, "/org/repo")
    }

    func testNormalizesGitHubURLWithoutScheme() throws {
        let url = try RepositoryURLValidator.normalize("github.com/org/repo")
        XCTAssertEqual(url.absoluteString, "https://github.com/org/repo")
    }

    func testStripsQueryAndFragment() throws {
        let url = try RepositoryURLValidator.normalize("https://github.com/org/repo?tab=readme#main")
        XCTAssertEqual(url.path, "/org/repo")
        XCTAssertNil(url.query)
        XCTAssertNil(url.fragment)
    }

    func testTrimsWhitespace() throws {
        let url = try RepositoryURLValidator.normalize("  https://github.com/org/repo  ")
        XCTAssertEqual(url.path, "/org/repo")
    }

    func testNormalizesGitLabURL() throws {
        let url = try RepositoryURLValidator.normalize("https://gitlab.com/group/project")
        XCTAssertEqual(url.host, "gitlab.com")
        XCTAssertEqual(url.path, "/group/project")
    }

    func testNormalizesBitbucketURL() throws {
        let url = try RepositoryURLValidator.normalize("https://bitbucket.org/team/repo")
        XCTAssertEqual(url.host, "bitbucket.org")
        XCTAssertEqual(url.path, "/team/repo")
    }

    func testNormalizesWWWGitHubURL() throws {
        let url = try RepositoryURLValidator.normalize("https://www.github.com/org/repo")
        XCTAssertEqual(url.host, "www.github.com")
        XCTAssertEqual(url.path, "/org/repo")
    }

    func testCloneURLAppendsGitExtension() throws {
        let normalized = try RepositoryURLValidator.normalize("https://github.com/org/repo")
        let cloneURL = RepositoryURLValidator.cloneURL(for: normalized)
        XCTAssertEqual(cloneURL.absoluteString, "https://github.com/org/repo.git")
    }

    // MARK: - Invalid URLs

    func testRejectsEmptyString() {
        assertThrowsRepositoryError(try RepositoryURLValidator.normalize(""), expected: .empty)
    }

    func testRejectsWhitespaceOnly() {
        assertThrowsRepositoryError(try RepositoryURLValidator.normalize("   "), expected: .empty)
    }

    func testRejectsUnsupportedHost() {
        assertThrowsRepositoryError(
            try RepositoryURLValidator.normalize("https://example.com/a/b"),
            expected: .invalidURL("https://example.com/a/b")
        )
    }

    func testRejectsHTTPScheme() {
        assertThrowsRepositoryError(
            try RepositoryURLValidator.normalize("http://github.com/org/repo"),
            expected: .invalidURL("http://github.com/org/repo")
        )
    }

    func testRejectsDeepPath() {
        assertThrowsRepositoryError(
            try RepositoryURLValidator.normalize("https://github.com/a/b/tree/main"),
            expected: .pathNotAllowed
        )
    }

    func testRejectsSingleSegmentPath() {
        assertThrowsRepositoryError(
            try RepositoryURLValidator.normalize("https://github.com/org"),
            expected: .pathNotAllowed
        )
    }

    func testRejectsTripleSegmentPath() {
        assertThrowsRepositoryError(
            try RepositoryURLValidator.normalize("https://github.com/org/repo/extra"),
            expected: .pathNotAllowed
        )
    }

    func testRejectsPathTraversalSegments() {
        assertThrowsRepositoryError(
            try RepositoryURLValidator.normalize("https://github.com/org/../secret"),
            expected: .pathNotAllowed
        )
    }

    func testRejectsNonStandardPort() {
        assertThrowsRepositoryError(
            try RepositoryURLValidator.normalize("https://github.com:8443/org/repo"),
            expected: .invalidURL("https://github.com:8443/org/repo")
        )
    }

    func testRejectsDotSegment() {
        assertThrowsRepositoryError(
            try RepositoryURLValidator.normalize("https://github.com/./repo"),
            expected: .invalidURL("https://github.com/./repo")
        )
    }

    func testErrorDescriptionsAreHumanReadable() {
        XCTAssertEqual(RepositoryURLError.empty.errorDescription, "Repository URL is required.")
        XCTAssertEqual(
            RepositoryURLError.unsupportedHost("evil.com").errorDescription,
            "Unsupported git host: evil.com. Only public GitHub, GitLab, and Bitbucket HTTPS URLs are supported."
        )
        XCTAssertEqual(
            RepositoryURLError.pathNotAllowed.errorDescription,
            "Repository URL must point to a repository root, not a file or subdirectory."
        )
    }

    private func assertThrowsRepositoryError(
        _ expression: @autoclosure () throws -> URL,
        expected: RepositoryURLError,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(try expression(), file: file, line: line) { error in
            guard let repoError = error as? RepositoryURLError else {
                XCTFail("Expected RepositoryURLError, got \(error)", file: file, line: line)
                return
            }
            switch (repoError, expected) {
            case (.empty, .empty),
                 (.pathNotAllowed, .pathNotAllowed):
                break
            case let (.unsupportedHost(lhs), .unsupportedHost(rhs)):
                XCTAssertEqual(lhs, rhs, file: file, line: line)
            case let (.invalidURL(lhs), .invalidURL(rhs)):
                XCTAssertEqual(lhs, rhs, file: file, line: line)
            default:
                XCTFail("Expected \(expected), got \(repoError)", file: file, line: line)
            }
        }
    }
}
