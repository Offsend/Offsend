import Foundation
import WorkspacePolicyCore

public struct ManagedIgnoreDriftFinding: Sendable, Equatable {
    public let relativePath: String
    public let missingPatterns: [String]

    public init(relativePath: String, missingPatterns: [String]) {
        self.relativePath = relativePath
        self.missingPatterns = missingPatterns
    }
}

/// Detects when existing AI ignore files are missing patterns from `ignore.patterns`.
public enum OffsendManagedIgnoreDrift: Sendable {
    public static func findings(
        directoryURL: URL,
        patterns: [String],
        configuration: AIWorkspacePrivacyAuditConfiguration = .default,
        fileManager: FileManager = .default
    ) -> [ManagedIgnoreDriftFinding] {
        let root = directoryURL.standardizedFileURL
        let expected = Set(OffsendManagedIgnoreBlock.normalizePatterns(patterns))
        guard !expected.isEmpty else { return [] }

        let targets = OffsendIgnoreSyncService.managedIgnoreRelativePaths(configuration: configuration)
        var findings: [ManagedIgnoreDriftFinding] = []

        for relativePath in targets {
            let url = root.appendingPathComponent(relativePath)
            guard fileManager.fileExists(atPath: url.path),
                  let contents = try? String(contentsOf: url, encoding: .utf8) else {
                continue
            }
            let present: Set<String>
            if let managed = OffsendManagedIgnoreBlock.patterns(in: contents) {
                present = Set(managed)
            } else {
                present = Set(
                    contents
                        .components(separatedBy: .newlines)
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty && !$0.hasPrefix("#") }
                )
            }
            let missing = expected.subtracting(present).sorted()
            if !missing.isEmpty {
                findings.append(
                    ManagedIgnoreDriftFinding(relativePath: relativePath, missingPatterns: missing)
                )
            }
        }
        return findings
    }
}
