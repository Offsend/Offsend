import Foundation

public enum HookInstallationState: String, Sendable, Equatable {
    case notInstalled
    case installed
    case modified
}

public struct HookStatusReport: Equatable, Sendable {
    public let repositoryPath: String
    public let hookType: HookType
    public let hookPath: String
    public let state: HookInstallationState
    public let scriptPreview: String?
    public let projectConfigPath: String?

    public init(
        repositoryPath: String,
        hookType: HookType,
        hookPath: String,
        state: HookInstallationState,
        scriptPreview: String? = nil,
        projectConfigPath: String? = nil
    ) {
        self.repositoryPath = repositoryPath
        self.hookType = hookType
        self.hookPath = hookPath
        self.state = state
        self.scriptPreview = scriptPreview
        self.projectConfigPath = projectConfigPath
    }
}
