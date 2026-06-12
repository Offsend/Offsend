import DetectionCore
import Foundation
import RiskScoringCore
import WorkspacePolicyCore

public enum CheckFailPolicy: String, Sendable, CaseIterable {
    case block
    case warn
    case none
}

public enum CheckOutputFormat: String, Sendable, CaseIterable {
    case text
    case json
}

public struct FileCheckFinding: Equatable, Sendable {
    public let relativePath: String
    public let line: Int
    public let entityType: SensitiveEntityType
    public let recommendedAction: RecommendedAction
    public let hasCriticalSecret: Bool

    public init(
        relativePath: String,
        line: Int,
        entityType: SensitiveEntityType,
        recommendedAction: RecommendedAction,
        hasCriticalSecret: Bool
    ) {
        self.relativePath = relativePath
        self.line = line
        self.entityType = entityType
        self.recommendedAction = recommendedAction
        self.hasCriticalSecret = hasCriticalSecret
    }
}

public struct FileCheckIssue: Equatable, Sendable {
    public let relativePath: String
    public let message: String

    public init(relativePath: String, message: String) {
        self.relativePath = relativePath
        self.message = message
    }
}

public struct PolicyCheckFinding: Equatable, Sendable {
    public let message: String
    public let status: AIWorkspacePrivacyAuditStatus

    public init(message: String, status: AIWorkspacePrivacyAuditStatus) {
        self.message = message
        self.status = status
    }
}

public struct CheckReport: Equatable, Sendable {
    public let fileFindings: [FileCheckFinding]
    public let fileIssues: [FileCheckIssue]
    public let policyFindings: [PolicyCheckFinding]
    public let failPolicy: CheckFailPolicy

    public init(
        fileFindings: [FileCheckFinding],
        fileIssues: [FileCheckIssue] = [],
        policyFindings: [PolicyCheckFinding] = [],
        failPolicy: CheckFailPolicy
    ) {
        self.fileFindings = fileFindings
        self.fileIssues = fileIssues
        self.policyFindings = policyFindings
        self.failPolicy = failPolicy
    }

    public var shouldFail: Bool {
        switch failPolicy {
        case .none:
            return false
        case .block:
            return hasBlockingFindings
        case .warn:
            return hasWarningFindings
        }
    }

    public var hasBlockingFindings: Bool {
        fileFindings.contains { $0.recommendedAction == .block || $0.hasCriticalSecret }
            || policyFindings.contains { $0.status == .fail }
    }

    public var hasWarningFindings: Bool {
        hasBlockingFindings
            || fileFindings.contains { $0.recommendedAction == .warn || $0.recommendedAction == .mask }
            || policyFindings.contains { $0.status == .warning }
    }

    public var blockingCount: Int {
        fileFindings.filter { $0.recommendedAction == .block || $0.hasCriticalSecret }.count
            + policyFindings.filter { $0.status == .fail }.count
    }

    public var warningCount: Int {
        fileFindings.filter { $0.recommendedAction == .warn || $0.recommendedAction == .mask }.count
            + policyFindings.filter { $0.status == .warning }.count
    }
}
