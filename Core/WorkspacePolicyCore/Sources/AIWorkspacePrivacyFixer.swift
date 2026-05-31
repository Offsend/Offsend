import Foundation

public final class AIWorkspacePrivacyFixer {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func fix(
        result: AIWorkspacePrivacyAuditResult,
        configuration: AIWorkspacePrivacyAuditConfiguration = .default,
        selection: AIWorkspacePrivacyFixSelection? = nil
    ) -> AIWorkspacePrivacyFixResult {
        let rootURL = result.directoryURL.standardizedFileURL
        guard isWritableDirectory(rootURL) else {
            return AIWorkspacePrivacyFixResult(
                createdRelativePaths: [],
                updatedRelativePaths: [],
                errors: [
                    AIWorkspacePrivacyAuditError(
                        id: "directory-not-writable",
                        message: "The selected directory is not writable."
                    )
                ]
            )
        }

        var createdRelativePaths: Set<String> = []
        var updatedRelativePaths: Set<String> = []
        var errors: [AIWorkspacePrivacyAuditError] = []

        for finding in result.ruleFindings where !finding.isSatisfied && finding.rule.severity != .informational {
            if let selection, !selection.ruleIDs.contains(finding.rule.id) {
                continue
            }
            guard let fix = configuration.rules.first(where: { $0.id == finding.rule.id })?.fix ?? finding.rule.fix else {
                continue
            }
            switch applyFix(fix, in: rootURL) {
            case .created(let relativePath):
                createdRelativePaths.insert(relativePath)
            case .updated(let relativePath):
                updatedRelativePaths.insert(relativePath)
            case .unchanged:
                break
            case .failed(let error):
                errors.append(error)
            }
        }

        let missingPatterns = result.missingSensitivePatterns.filter { finding in
            guard let selection else { return true }
            return selection.patternIDs.contains(finding.pattern.id)
        }
        if !missingPatterns.isEmpty {
            let lines = missingPatterns.map(\.pattern.canonicalIgnoreLine)
            let targetPaths = AIWorkspacePrivacyFixPlanner.patternTargetRelativePaths(
                for: result,
                configuration: configuration,
                selection: selection,
                createdRelativePaths: createdRelativePaths
            )
            if targetPaths.isEmpty {
                errors.append(
                    AIWorkspacePrivacyAuditError(
                        id: "no-pattern-target-files",
                        message: "Select at least one policy ignore file (for example .cursorignore) to apply the chosen sensitive patterns."
                    )
                )
            } else {
                for relativePath in targetPaths {
                    switch appendMissingLines(lines, to: relativePath, in: rootURL) {
                    case .created(let path):
                        createdRelativePaths.insert(path)
                    case .updated(let path):
                        updatedRelativePaths.insert(path)
                    case .unchanged:
                        break
                    case .failed(let error):
                        errors.append(error)
                    }
                }
            }
        }

        return AIWorkspacePrivacyFixResult(
            createdRelativePaths: createdRelativePaths.sorted(),
            updatedRelativePaths: updatedRelativePaths.sorted(),
            errors: errors
        )
    }

    private func applyFix(_ fix: AIWorkspacePrivacyFileFix, in rootURL: URL) -> FileWriteOutcome {
        switch fix.strategy {
        case .createIfMissing:
            return createFileIfMissing(fix, in: rootURL)
        case .mergeLines:
            return mergeLines(from: fix, in: rootURL)
        }
    }

    private func createFileIfMissing(_ fix: AIWorkspacePrivacyFileFix, in rootURL: URL) -> FileWriteOutcome {
        guard let url = safeURL(for: fix.relativePath, in: rootURL) else {
            return .failed(invalidPathError(fix.relativePath))
        }

        do {
            try fileManager.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            return try coordinateFileWrite(at: url) { coordinatedURL in
                guard !fileManager.fileExists(atPath: coordinatedURL.path) else {
                    return .unchanged
                }
                try normalizedContents(fix.contents).write(
                    to: coordinatedURL,
                    atomically: true,
                    encoding: .utf8
                )
                return .created(fix.relativePath)
            }
        } catch {
            return .failed(
                AIWorkspacePrivacyAuditError(
                    id: "create-file-failed",
                    message: "Could not create \(fix.relativePath): \(error.localizedDescription)"
                )
            )
        }
    }

    private func mergeLines(from fix: AIWorkspacePrivacyFileFix, in rootURL: URL) -> FileWriteOutcome {
        guard let url = safeURL(for: fix.relativePath, in: rootURL) else {
            return .failed(invalidPathError(fix.relativePath))
        }

        if !fileManager.fileExists(atPath: url.path) {
            return writeContents(fix.contents, to: url, relativePath: fix.relativePath, didCreateFile: true)
        }

        let lines = IgnoreFileParser.patternLines(in: fix.contents)
        guard !lines.isEmpty else { return .unchanged }

        switch appendMissingLines(lines, to: fix.relativePath, in: rootURL) {
        case .created(let path):
            return .created(path)
        case .updated(let path):
            return .updated(path)
        case .unchanged:
            return .unchanged
        case .failed(let error):
            return .failed(error)
        }
    }

    private func appendMissingLines(_ lines: [String], to relativePath: String, in rootURL: URL) -> LineAppendOutcome {
        guard !lines.isEmpty else { return .unchanged }
        guard let url = safeURL(for: relativePath, in: rootURL) else {
            return .failed(invalidPathError(relativePath))
        }

        do {
            try fileManager.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let fileExists = fileManager.fileExists(atPath: url.path)
            let options: NSFileCoordinator.WritingOptions = fileExists ? .forMerging : []

            return try coordinateFileWrite(at: url, options: options) { coordinatedURL in
                let existingContents: String
                let didCreateFile: Bool
                if fileManager.fileExists(atPath: coordinatedURL.path) {
                    existingContents = try String(contentsOf: coordinatedURL, encoding: .utf8)
                    didCreateFile = false
                } else {
                    existingContents = IgnoreFileParser.defaultHeader + "\n"
                    didCreateFile = true
                }

                let existingPatterns = IgnoreFileParser.patterns(in: existingContents)
                let missingLines = lines.filter { !existingPatterns.contains($0) }
                guard !missingLines.isEmpty else { return .unchanged }

                let separator = existingContents.hasSuffix("\n") ? "" : "\n"
                let updatedContents = existingContents + separator + missingLines.joined(separator: "\n") + "\n"
                try updatedContents.write(to: coordinatedURL, atomically: true, encoding: .utf8)
                return didCreateFile ? .created(relativePath) : .updated(relativePath)
            }
        } catch {
            return .failed(
                AIWorkspacePrivacyAuditError(
                    id: "append-patterns-failed",
                    message: "Could not update \(relativePath): \(error.localizedDescription)"
                )
            )
        }
    }

    private func writeContents(
        _ contents: String,
        to url: URL,
        relativePath: String,
        didCreateFile: Bool
    ) -> FileWriteOutcome {
        do {
            try fileManager.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            return try coordinateFileWrite(at: url) { coordinatedURL in
                guard !fileManager.fileExists(atPath: coordinatedURL.path) else {
                    return .unchanged
                }
                try normalizedContents(contents).write(
                    to: coordinatedURL,
                    atomically: true,
                    encoding: .utf8
                )
                return didCreateFile ? .created(relativePath) : .updated(relativePath)
            }
        } catch {
            return .failed(
                AIWorkspacePrivacyAuditError(
                    id: "create-file-failed",
                    message: "Could not create \(relativePath): \(error.localizedDescription)"
                )
            )
        }
    }

    private func coordinateFileWrite<T>(
        at url: URL,
        options: NSFileCoordinator.WritingOptions = [],
        _ work: (URL) throws -> T
    ) throws -> T {
        let coordinator = NSFileCoordinator()
        var coordinationError: NSError?
        var capturedResult: Result<T, Error>?

        coordinator.coordinate(
            writingItemAt: url,
            options: options,
            error: &coordinationError
        ) { coordinatedURL in
            capturedResult = Result { try work(coordinatedURL) }
        }

        if let coordinationError {
            throw coordinationError
        }
        guard let capturedResult else {
            throw NSError(
                domain: "AIWorkspacePrivacyFixer",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "File coordination did not complete."]
            )
        }
        return try capturedResult.get()
    }

    private func isWritableDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return false
        }
        return fileManager.isWritableFile(atPath: url.path)
    }

    private func safeURL(for relativePath: String, in rootURL: URL) -> URL? {
        guard !relativePath.hasPrefix("/") else { return nil }
        let rootPath = rootURL.standardizedFileURL.path
        let url = rootURL.appendingPathComponent(relativePath).standardizedFileURL
        // Lexical containment rejects `..` escapes.
        guard url.path == rootPath || url.path.hasPrefix(rootPath + "/") else {
            return nil
        }
        // Symlink containment: resolve the nearest existing ancestor and ensure it
        // still lives under the resolved root, so a symlinked parent directory cannot
        // redirect writes outside the selected directory.
        let resolvedRootPath = rootURL.standardizedFileURL.resolvingSymlinksInPath().path
        let resolvedAncestorPath = nearestExistingAncestor(of: url).resolvingSymlinksInPath().path
        guard resolvedAncestorPath == resolvedRootPath
            || resolvedAncestorPath.hasPrefix(resolvedRootPath + "/")
        else {
            return nil
        }
        return url
    }

    private func nearestExistingAncestor(of url: URL) -> URL {
        var current = url.standardizedFileURL
        while !fileManager.fileExists(atPath: current.path) {
            let parent = current.deletingLastPathComponent()
            guard parent.path != current.path else { break }
            current = parent
        }
        return current
    }

    private func normalizedContents(_ contents: String) -> String {
        contents.hasSuffix("\n") ? contents : contents + "\n"
    }
}

private enum FileWriteOutcome {
    case created(String)
    case updated(String)
    case unchanged
    case failed(AIWorkspacePrivacyAuditError)
}

private enum LineAppendOutcome {
    case created(String)
    case updated(String)
    case unchanged
    case failed(AIWorkspacePrivacyAuditError)
}

private extension AIWorkspacePrivacyFixer {
    func invalidPathError(_ relativePath: String) -> AIWorkspacePrivacyAuditError {
        AIWorkspacePrivacyAuditError(
            id: "invalid-fix-path",
            message: "The fix path is outside the selected directory: \(relativePath)"
        )
    }
}
