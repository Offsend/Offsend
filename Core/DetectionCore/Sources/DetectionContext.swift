import Foundation

/// How dangerous a finding's *location* is. The detector finds the same entities everywhere; the tier
/// only shifts how risk is scored: a secret-shaped path raises non-secret PII, while docs/tests lower it.
/// Confirmed secrets (keys, JWT, …) always block regardless of tier — see `RiskScoringEngine`.
public enum FileSensitivityTier: String, Equatable, Sendable {
    /// `.env`, `config.*`, `secrets.*`, `*.tfvars`, key material, `.ssh`/`.aws` — a real key here is severe.
    case secretsConfig
    /// Application source code and anything unclassified. Current behavior, no adjustment.
    case neutral
    /// READMEs, `*.md`, `docs/`, `tests/`, fixtures, `*.example` — usually placeholders or sample data.
    case docsOrTests
}

/// Carries the file-location context into risk scoring. Clipboard scans have no path, so they use `.neutral`.
public struct DetectionContext: Equatable, Sendable {
    public let sensitivity: FileSensitivityTier

    public init(sensitivity: FileSensitivityTier) {
        self.sensitivity = sensitivity
    }

    /// Classifies the tier from a file path (relative or absolute, real or staged-export mirror).
    public init(path: String) {
        self.sensitivity = FileSensitivityClassifier.tier(forPath: path)
    }

    public static let neutral = DetectionContext(sensitivity: .neutral)
}

public enum FileSensitivityClassifier {
    /// `.env.example`, `config.sample`, `secrets.template`, `*.dist` — meant to ship placeholder values,
    /// so they are treated as docs even though the base name looks like a secret store.
    private static let placeholderMarkers: Set<String> = ["example", "sample", "template", "dist", "tmpl"]

    /// Base names (without extension) that typically hold real configuration/credentials.
    private static let secretBaseNames: Set<String> = ["config", "configuration", "secrets", "secret", "credentials"]

    /// Extensions that are key material or secret-bearing config.
    private static let secretExtensions: Set<String> = [
        "env", "tfvars", "pem", "key", "p12", "pfx", "keystore", "jks", "ppk", "asc",
    ]

    /// Exact filenames for SSH/PGP private keys.
    private static let secretFileNames: Set<String> = ["id_rsa", "id_dsa", "id_ecdsa", "id_ed25519"]

    /// Directory segments that indicate sample/test/doc material.
    private static let docsOrTestsSegments: Set<String> = [
        "test", "tests", "__tests__", "spec", "specs", "docs", "doc", "example", "examples",
        "fixtures", "fixture", "__fixtures__", "__mocks__", "mocks", "sample", "samples", "testdata",
    ]

    /// Doc-style file extensions.
    private static let docExtensions: Set<String> = ["md", "markdown", "mdx", "rst", "adoc"]

    /// Base names that are project docs regardless of extension.
    private static let docBaseNames: Set<String> = [
        "readme", "changelog", "license", "licence", "contributing", "authors", "notice", "codeowners",
    ]

    public static func tier(forPath rawPath: String) -> FileSensitivityTier {
        let path = rawPath.lowercased()
        let segments = path.split(whereSeparator: { $0 == "/" || $0 == "\\" }).map(String.init)
        let fileName = segments.last ?? path
        let baseName = baseNameWithoutExtension(fileName)
        let ext = fileExtension(fileName)
        let isPlaceholder = isPlaceholderLike(fileName)

        if !isPlaceholder, isSecretsConfig(fileName: fileName, baseName: baseName, ext: ext, segments: segments) {
            return .secretsConfig
        }
        if isDocsOrTests(fileName: fileName, baseName: baseName, ext: ext, segments: segments) {
            return .docsOrTests
        }
        return .neutral
    }

    private static func isPlaceholderLike(_ fileName: String) -> Bool {
        placeholderMarkers.contains { fileName.contains($0) }
    }

    private static func isSecretsConfig(fileName: String, baseName: String, ext: String, segments: [String]) -> Bool {
        if fileName == ".env" || fileName.hasPrefix(".env.") { return true }
        if secretFileNames.contains(fileName) { return true }
        if secretExtensions.contains(ext) { return true }
        if secretBaseNames.contains(baseName) { return true }
        if segments.dropLast().contains(where: { $0 == ".ssh" || $0 == ".aws" || $0 == ".gnupg" }) { return true }
        return false
    }

    private static func isDocsOrTests(fileName: String, baseName: String, ext: String, segments: [String]) -> Bool {
        if docExtensions.contains(ext) { return true }
        if docBaseNames.contains(baseName) { return true }
        if segments.dropLast().contains(where: docsOrTestsSegments.contains) { return true }
        // `foo.test.ts`, `foo.spec.js`, `foo_test.go`, `test_foo.py`.
        if baseName.hasSuffix(".test") || baseName.hasSuffix(".spec")
            || baseName.hasSuffix("_test") || baseName.hasSuffix("_spec")
            || baseName.hasPrefix("test_") {
            return true
        }
        return false
    }

    /// Lowercased extension after the last dot, empty when there is none (or the name is a dotfile like `.env`).
    private static func fileExtension(_ fileName: String) -> String {
        guard let dot = fileName.lastIndex(of: "."), dot != fileName.startIndex else { return "" }
        return String(fileName[fileName.index(after: dot)...])
    }

    /// Everything before the last dot (or the whole name when there is no extension). Keeps inner dots
    /// so `foo.test` is preserved for the `.test` suffix check above.
    private static func baseNameWithoutExtension(_ fileName: String) -> String {
        guard let dot = fileName.lastIndex(of: "."), dot != fileName.startIndex else { return fileName }
        return String(fileName[..<dot])
    }
}
