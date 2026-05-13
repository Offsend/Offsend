import DetectionCore
import Foundation
import MaskingCore

public enum DefaultNoRiskAction: String, Codable, CaseIterable, Identifiable {
    case pasteOriginal
    case copyOriginal
    case showToast

    public var id: String { rawValue }
}

public enum RestoreBehavior: String, Codable, CaseIterable, Identifiable {
    case copyToClipboard
    case pasteIntoActiveApp

    public var id: String { rawValue }
}

public struct ExcludedClipboardApplication: Codable, Equatable, Identifiable {
    public var displayName: String
    public var bundleIdentifier: String

    public var id: String { bundleIdentifier }

    public init(displayName: String, bundleIdentifier: String) {
        self.displayName = displayName
        self.bundleIdentifier = bundleIdentifier
    }
}

public struct AppSettings: Codable, Equatable {
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
    }

    public init(
        hasCompletedOnboarding: Bool = false,
        protectionEnabled: Bool = true,
        clipboardMonitoringEnabled: Bool = true,
        launchAtLogin: Bool = false,
        defaultNoRiskAction: DefaultNoRiskAction = .pasteOriginal,
        enabledDetectors: Set<SensitiveEntityType> = Set(SensitiveEntityType.allCases),
        mappingTTL: MappingTTL = .sixHours,
        restoreBehavior: RestoreBehavior = .copyToClipboard,
        preserveOriginalClipboard: Bool = true,
        analyticsOptIn: Bool = false,
        allowPasteOriginalForCriticalSecrets: Bool = false,
        excludedClipboardApplications: [ExcludedClipboardApplication] = [
            ExcludedClipboardApplication(displayName: "Figma", bundleIdentifier: "com.figma.Desktop")
        ]
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
            ) ?? AppSettings.default.excludedClipboardApplications
        )
    }

    public static let `default` = AppSettings()
}

public struct LicenseState: Codable, Equatable {
    public enum Plan: String, Codable, CaseIterable {
        case free
        case pro
    }

    public var plan: Plan
    public var maskedThisMonth: Int
    /// `yyyy-MM` in the user’s calendar / time zone; when it changes, `maskedThisMonth` resets for the free-tier quota.
    public var freeMaskedUsageMonthKey: String?
    /// Legacy field from pre–magic-code builds; not written to Keychain.
    public var licenseEmail: String?
    public var activatedAt: Date?
    /// Legacy grace end; superseded by `graceUntil` when set.
    public var offlineGraceExpiresAt: Date?

    public var subscriptionExpiresAt: Date?
    public var graceUntil: Date?
    public var licenseBillingState: String?
    public var licenseStatus: String?
    public var lastLicenseValidationAt: Date?

    enum CodingKeys: String, CodingKey {
        case plan
        case maskedThisMonth
        case freeMaskedUsageMonthKey
        case licenseEmail
        case activatedAt
        case offlineGraceExpiresAt
        case subscriptionExpiresAt
        case graceUntil
        case licenseBillingState
        case licenseStatus
        case lastLicenseValidationAt
    }

    public init(
        plan: Plan = .free,
        maskedThisMonth: Int = 0,
        freeMaskedUsageMonthKey: String? = nil,
        licenseEmail: String? = nil,
        activatedAt: Date? = nil,
        offlineGraceExpiresAt: Date? = nil,
        subscriptionExpiresAt: Date? = nil,
        graceUntil: Date? = nil,
        licenseBillingState: String? = nil,
        licenseStatus: String? = nil,
        lastLicenseValidationAt: Date? = nil
    ) {
        self.plan = plan
        self.maskedThisMonth = maskedThisMonth
        self.freeMaskedUsageMonthKey = freeMaskedUsageMonthKey
        self.licenseEmail = licenseEmail
        self.activatedAt = activatedAt
        self.offlineGraceExpiresAt = offlineGraceExpiresAt
        self.subscriptionExpiresAt = subscriptionExpiresAt
        self.graceUntil = graceUntil
        self.licenseBillingState = licenseBillingState
        self.licenseStatus = licenseStatus
        self.lastLicenseValidationAt = lastLicenseValidationAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.plan = try container.decode(Plan.self, forKey: .plan)
        self.maskedThisMonth = try container.decodeIfPresent(Int.self, forKey: .maskedThisMonth) ?? 0
        self.freeMaskedUsageMonthKey = try container.decodeIfPresent(String.self, forKey: .freeMaskedUsageMonthKey)
        self.licenseEmail = try container.decodeIfPresent(String.self, forKey: .licenseEmail)
        self.activatedAt = try container.decodeIfPresent(Date.self, forKey: .activatedAt)
        self.offlineGraceExpiresAt = try container.decodeIfPresent(Date.self, forKey: .offlineGraceExpiresAt)
        self.subscriptionExpiresAt = try container.decodeIfPresent(Date.self, forKey: .subscriptionExpiresAt)
        var decodedGrace = try container.decodeIfPresent(Date.self, forKey: .graceUntil)
        if decodedGrace == nil {
            decodedGrace = self.offlineGraceExpiresAt
        }
        self.graceUntil = decodedGrace
        self.licenseBillingState = try container.decodeIfPresent(String.self, forKey: .licenseBillingState)
        self.licenseStatus = try container.decodeIfPresent(String.self, forKey: .licenseStatus)
        self.lastLicenseValidationAt = try container.decodeIfPresent(Date.self, forKey: .lastLicenseValidationAt)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(plan, forKey: .plan)
        try container.encode(maskedThisMonth, forKey: .maskedThisMonth)
        try container.encodeIfPresent(freeMaskedUsageMonthKey, forKey: .freeMaskedUsageMonthKey)
        try container.encodeIfPresent(licenseEmail, forKey: .licenseEmail)
        try container.encodeIfPresent(activatedAt, forKey: .activatedAt)
        try container.encodeIfPresent(offlineGraceExpiresAt, forKey: .offlineGraceExpiresAt)
        try container.encodeIfPresent(subscriptionExpiresAt, forKey: .subscriptionExpiresAt)
        try container.encodeIfPresent(graceUntil, forKey: .graceUntil)
        try container.encodeIfPresent(licenseBillingState, forKey: .licenseBillingState)
        try container.encodeIfPresent(licenseStatus, forKey: .licenseStatus)
        try container.encodeIfPresent(lastLicenseValidationAt, forKey: .lastLicenseValidationAt)
    }

    /// Gregorian `yyyy-MM` in the user’s current calendar / time zone.
    public static func freeMaskedUsageMonthKey(for date: Date = Date(), calendar: Calendar = .current) -> String {
        let y = calendar.component(.year, from: date)
        let m = calendar.component(.month, from: date)
        return String(format: "%04d-%02d", y, m)
    }

    /// Keeps `maskedThisMonth` aligned with the current calendar month (free-tier masked paste quota).
    public mutating func reconcileFreeTierMaskedUsageCountForCurrentMonth(
        now: Date = Date(),
        calendar: Calendar = .current
    ) {
        let key = Self.freeMaskedUsageMonthKey(for: now, calendar: calendar)
        if freeMaskedUsageMonthKey == nil {
            freeMaskedUsageMonthKey = key
            return
        }
        if freeMaskedUsageMonthKey != key {
            freeMaskedUsageMonthKey = key
            maskedThisMonth = 0
        }
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
