import DetectionCore
import Foundation
import MaskingCore

public enum DefaultNoRiskAction: String, Codable, CaseIterable, Identifiable, Sendable {
    case pasteOriginal
    case copyOriginal
    case showToast

    public var id: String { rawValue }
}

public enum RestoreBehavior: String, Codable, CaseIterable, Identifiable, Sendable {
    case copyToClipboard
    case pasteIntoActiveApp

    public var id: String { rawValue }
}

public struct ExcludedClipboardApplication: Codable, Equatable, Identifiable, Sendable {
    public var displayName: String
    public var bundleIdentifier: String

    public var id: String { bundleIdentifier }

    public init(displayName: String, bundleIdentifier: String) {
        self.displayName = displayName
        self.bundleIdentifier = bundleIdentifier
    }

    public static func matches(
        bundleIdentifier: String,
        in excludedApplications: [ExcludedClipboardApplication]
    ) -> ExcludedClipboardApplication? {
        excludedApplications.first {
            $0.bundleIdentifier.caseInsensitiveCompare(bundleIdentifier) == .orderedSame
        }
    }
}

public struct AppSettings: Codable, Equatable, Sendable {
    public var hasCompletedOnboarding: Bool
    public var protectionEnabled: Bool
    public var clipboardMonitoringEnabled: Bool
    public var launchAtLogin: Bool
    public var defaultNoRiskAction: DefaultNoRiskAction
    public var enabledDetectors: Set<SensitiveEntityType>
    public var mappingTTL: MappingTTL
    public var restoreBehavior: RestoreBehavior
    public var preserveOriginalClipboard: Bool
    public var analyticsOptIn: Bool
    public var allowPasteOriginalForCriticalSecrets: Bool
    public var excludedClipboardApplications: [ExcludedClipboardApplication]

    // MARK: AI Detection

    public var aiDetectionEnabled: Bool
    public var selectedAIModelID: String?

    // MARK: Directory Check

    /// IDs of `AIWorkspacePrivacyRule` the user has disabled. Required rules are still enforced regardless of this set.
    public var directoryCheckDisabledRuleIDs: Set<String>
    /// When true, the Directory Check Fix action shows a confirmation alert before writing files.
    public var directoryCheckConfirmFix: Bool
    /// Pro override for `AIWorkspacePrivacyIgnoreTemplate.contents`. `nil` keeps the built-in template.
    public var directoryCheckCustomIgnoreTemplate: String?
    /// Extra directory names skipped while walking the workspace (merged with the built-in list).
    public var directoryCheckExtraSkippedDirectories: [String]

    // MARK: Directory Watch

    public var directoryWatchEnabled: Bool
    public var watchedDirectories: [WatchedDirectory]
    public var directoryWatchNotifyOnDegrade: Bool

    private enum CodingKeys: String, CodingKey {
        case hasCompletedOnboarding
        case protectionEnabled
        case clipboardMonitoringEnabled
        case launchAtLogin
        case defaultNoRiskAction
        case enabledDetectors
        case mappingTTL
        case restoreBehavior
        case preserveOriginalClipboard
        case analyticsOptIn
        case allowPasteOriginalForCriticalSecrets
        case excludedClipboardApplications
        case aiDetectionEnabled
        case selectedAIModelID
        case directoryCheckDisabledRuleIDs
        case directoryCheckConfirmFix
        case directoryCheckCustomIgnoreTemplate
        case directoryCheckExtraSkippedDirectories
        case directoryWatchEnabled
        case watchedDirectories
        case directoryWatchNotifyOnDegrade
    }

    public init(
        hasCompletedOnboarding: Bool = false,
        protectionEnabled: Bool = true,
        clipboardMonitoringEnabled: Bool = true,
        launchAtLogin: Bool = false,
        defaultNoRiskAction: DefaultNoRiskAction = .pasteOriginal,
        enabledDetectors: Set<SensitiveEntityType> = Set(SensitiveEntityType.allCases),
        mappingTTL: MappingTTL = .oneHour,
        restoreBehavior: RestoreBehavior = .copyToClipboard,
        preserveOriginalClipboard: Bool = true,
        analyticsOptIn: Bool = false,
        allowPasteOriginalForCriticalSecrets: Bool = false,
        excludedClipboardApplications: [ExcludedClipboardApplication] = [
            ExcludedClipboardApplication(displayName: "Figma", bundleIdentifier: "com.figma.Desktop")
        ],
        aiDetectionEnabled: Bool = false,
        selectedAIModelID: String? = nil,
        directoryCheckDisabledRuleIDs: Set<String> = [],
        directoryCheckConfirmFix: Bool = true,
        directoryCheckCustomIgnoreTemplate: String? = nil,
        directoryCheckExtraSkippedDirectories: [String] = [],
        directoryWatchEnabled: Bool = false,
        watchedDirectories: [WatchedDirectory] = [],
        directoryWatchNotifyOnDegrade: Bool = true
    ) {
        self.hasCompletedOnboarding = hasCompletedOnboarding
        self.protectionEnabled = protectionEnabled
        self.clipboardMonitoringEnabled = clipboardMonitoringEnabled
        self.launchAtLogin = launchAtLogin
        self.defaultNoRiskAction = defaultNoRiskAction
        self.enabledDetectors = enabledDetectors
        self.mappingTTL = mappingTTL
        self.restoreBehavior = restoreBehavior
        self.preserveOriginalClipboard = preserveOriginalClipboard
        self.analyticsOptIn = analyticsOptIn
        self.allowPasteOriginalForCriticalSecrets = allowPasteOriginalForCriticalSecrets
        self.excludedClipboardApplications = excludedClipboardApplications
        self.aiDetectionEnabled = aiDetectionEnabled
        self.selectedAIModelID = selectedAIModelID
        self.directoryCheckDisabledRuleIDs = directoryCheckDisabledRuleIDs
        self.directoryCheckConfirmFix = directoryCheckConfirmFix
        self.directoryCheckCustomIgnoreTemplate = directoryCheckCustomIgnoreTemplate
        self.directoryCheckExtraSkippedDirectories = directoryCheckExtraSkippedDirectories
        self.directoryWatchEnabled = directoryWatchEnabled
        self.watchedDirectories = watchedDirectories
        self.directoryWatchNotifyOnDegrade = directoryWatchNotifyOnDegrade
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            hasCompletedOnboarding: try container.decode(Bool.self, forKey: .hasCompletedOnboarding),
            protectionEnabled: try container.decode(Bool.self, forKey: .protectionEnabled),
            clipboardMonitoringEnabled: try container.decode(Bool.self, forKey: .clipboardMonitoringEnabled),
            launchAtLogin: try container.decode(Bool.self, forKey: .launchAtLogin),
            defaultNoRiskAction: try container.decode(DefaultNoRiskAction.self, forKey: .defaultNoRiskAction),
            enabledDetectors: try container.decode(Set<SensitiveEntityType>.self, forKey: .enabledDetectors),
            mappingTTL: try container.decode(MappingTTL.self, forKey: .mappingTTL),
            restoreBehavior: try container.decode(RestoreBehavior.self, forKey: .restoreBehavior),
            preserveOriginalClipboard: try container.decode(Bool.self, forKey: .preserveOriginalClipboard),
            analyticsOptIn: try container.decode(Bool.self, forKey: .analyticsOptIn),
            allowPasteOriginalForCriticalSecrets: try container.decode(Bool.self, forKey: .allowPasteOriginalForCriticalSecrets),
            excludedClipboardApplications: try container.decodeIfPresent(
                [ExcludedClipboardApplication].self,
                forKey: .excludedClipboardApplications
            ) ?? AppSettings.default.excludedClipboardApplications,
            aiDetectionEnabled: try container.decodeIfPresent(Bool.self, forKey: .aiDetectionEnabled) ?? false,
            selectedAIModelID: try container.decodeIfPresent(String.self, forKey: .selectedAIModelID)
                ?? (try? decoder.container(keyedBy: LegacyCodingKeys.self))
                    .flatMap { try $0.decodeIfPresent(String.self, forKey: .selectedAIModelRepositoryID) } ?? nil,
            directoryCheckDisabledRuleIDs: try container.decodeIfPresent(
                Set<String>.self,
                forKey: .directoryCheckDisabledRuleIDs
            ) ?? [],
            directoryCheckConfirmFix: try container.decodeIfPresent(
                Bool.self,
                forKey: .directoryCheckConfirmFix
            ) ?? true,
            directoryCheckCustomIgnoreTemplate: try container.decodeIfPresent(
                String.self,
                forKey: .directoryCheckCustomIgnoreTemplate
            ),
            directoryCheckExtraSkippedDirectories: try container.decodeIfPresent(
                [String].self,
                forKey: .directoryCheckExtraSkippedDirectories
            ) ?? [],
            directoryWatchEnabled: try container.decodeIfPresent(Bool.self, forKey: .directoryWatchEnabled) ?? false,
            watchedDirectories: try container.decodeIfPresent([WatchedDirectory].self, forKey: .watchedDirectories) ?? [],
            directoryWatchNotifyOnDegrade: try container.decodeIfPresent(Bool.self, forKey: .directoryWatchNotifyOnDegrade) ?? true
        )
    }

    public static let `default` = AppSettings()
}

private enum LegacyCodingKeys: String, CodingKey {
    case selectedAIModelRepositoryID
}

public struct LicenseState: Codable, Equatable {
    public enum Plan: String, Codable, CaseIterable {
        case free
        case pro
    }

    public var plan: Plan
    public var activatedAt: Date?

    public var subscriptionExpiresAt: Date?
    public var graceUntil: Date?
    public var licenseBillingState: String?
    public var licenseStatus: String?
    public var lastLicenseValidationAt: Date?

    enum CodingKeys: String, CodingKey {
        case plan
        case activatedAt
        case subscriptionExpiresAt
        case graceUntil
        case licenseBillingState
        case licenseStatus
        case lastLicenseValidationAt
    }

    public init(
        plan: Plan = .free,
        activatedAt: Date? = nil,
        subscriptionExpiresAt: Date? = nil,
        graceUntil: Date? = nil,
        licenseBillingState: String? = nil,
        licenseStatus: String? = nil,
        lastLicenseValidationAt: Date? = nil
    ) {
        self.plan = plan
        self.activatedAt = activatedAt
        self.subscriptionExpiresAt = subscriptionExpiresAt
        self.graceUntil = graceUntil
        self.licenseBillingState = licenseBillingState
        self.licenseStatus = licenseStatus
        self.lastLicenseValidationAt = lastLicenseValidationAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.plan = try container.decode(Plan.self, forKey: .plan)
        self.activatedAt = try container.decodeIfPresent(Date.self, forKey: .activatedAt)
        self.subscriptionExpiresAt = try container.decodeIfPresent(Date.self, forKey: .subscriptionExpiresAt)
        self.graceUntil = try container.decodeIfPresent(Date.self, forKey: .graceUntil)
        self.licenseBillingState = try container.decodeIfPresent(String.self, forKey: .licenseBillingState)
        self.licenseStatus = try container.decodeIfPresent(String.self, forKey: .licenseStatus)
        self.lastLicenseValidationAt = try container.decodeIfPresent(Date.self, forKey: .lastLicenseValidationAt)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(plan, forKey: .plan)
        try container.encodeIfPresent(activatedAt, forKey: .activatedAt)
        try container.encodeIfPresent(subscriptionExpiresAt, forKey: .subscriptionExpiresAt)
        try container.encodeIfPresent(graceUntil, forKey: .graceUntil)
        try container.encodeIfPresent(licenseBillingState, forKey: .licenseBillingState)
        try container.encodeIfPresent(licenseStatus, forKey: .licenseStatus)
        try container.encodeIfPresent(lastLicenseValidationAt, forKey: .lastLicenseValidationAt)
    }

}

public struct LocalEvent: Codable, Identifiable, Equatable {
    public let id: UUID
    public var createdAt: Date
    public var type: String
    public var riskLevel: RiskLevel?
    public var metadata: [String: String]

    public init(id: UUID = UUID(), createdAt: Date = Date(), type: String, riskLevel: RiskLevel? = nil, metadata: [String: String] = [:]) {
        self.id = id
        self.createdAt = createdAt
        self.type = type
        self.riskLevel = riskLevel
        self.metadata = metadata
    }
}

public struct StoredMappingSummary: Codable, Identifiable, Equatable {
    public let id: UUID
    public var createdAt: Date
    public var expiresAt: Date?
    public var placeholderCount: Int

    public init(id: UUID, createdAt: Date, expiresAt: Date?, placeholderCount: Int) {
        self.id = id
        self.createdAt = createdAt
        self.expiresAt = expiresAt
        self.placeholderCount = placeholderCount
    }
}
