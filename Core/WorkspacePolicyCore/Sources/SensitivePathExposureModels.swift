import Foundation

public struct SensitivePathExposureScanLimits: Equatable, Sendable {
    public let maxFiles: Int?
    public let timeLimit: TimeInterval?

    public init(maxFiles: Int?, timeLimit: TimeInterval?) {
        self.maxFiles = maxFiles
        self.timeLimit = timeLimit
    }

    /// Production defaults for large workspaces.
    public static let `default` = SensitivePathExposureScanLimits(maxFiles: 100_000, timeLimit: 30)

    public static let unlimited = SensitivePathExposureScanLimits(maxFiles: nil, timeLimit: nil)
}

public enum SensitivePathExposureScanCompletion: Equatable, Sendable {
    case complete
    case truncated(maxFiles: Int, filesScanned: Int)
    case timedOut(timeLimit: TimeInterval, filesScanned: Int)

    public var isComplete: Bool {
        if case .complete = self { return true }
        return false
    }
}

public struct SensitivePathExposureIndex: Equatable, Sendable {
    public let sensitiveRelativePaths: Set<String>

    public init(sensitiveRelativePaths: Set<String>) {
        self.sensitiveRelativePaths = sensitiveRelativePaths
    }

    func merging(_ paths: Set<String>) -> SensitivePathExposureIndex {
        SensitivePathExposureIndex(sensitiveRelativePaths: sensitiveRelativePaths.union(paths))
    }
}

/// A project file whose path matches a curated sensitive pattern and is not covered
/// by any declared ignore rule in the effective ignore files.
public struct AIWorkspaceExposedFileFinding: Equatable, Identifiable, Sendable {
    public var id: String { relativePath }
    public let relativePath: String
    public let pattern: AIWorkspaceSensitivePattern

    public init(relativePath: String, pattern: AIWorkspaceSensitivePattern) {
        self.relativePath = relativePath
        self.pattern = pattern
    }
}

public struct SensitivePathExposureScanResult: Equatable, Sendable {
    public let exposedFiles: [AIWorkspaceExposedFileFinding]
    public let indexedSensitivePaths: Set<String>
    public let filesScanned: Int
    public let completion: SensitivePathExposureScanCompletion

    public init(
        exposedFiles: [AIWorkspaceExposedFileFinding],
        indexedSensitivePaths: Set<String> = [],
        filesScanned: Int = 0,
        completion: SensitivePathExposureScanCompletion = .complete
    ) {
        self.exposedFiles = exposedFiles.sorted { $0.relativePath < $1.relativePath }
        self.indexedSensitivePaths = indexedSensitivePaths
        self.filesScanned = filesScanned
        self.completion = completion
    }
}
