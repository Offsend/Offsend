import Foundation

public struct LicenseConfiguration: Sendable, Equatable {
    public var apiBaseURL: URL
    public var checkoutPlanId: String

    public init(apiBaseURL: URL, checkoutPlanId: String = "pro_annual") {
        self.apiBaseURL = apiBaseURL
        self.checkoutPlanId = checkoutPlanId
    }

    public static let production = LicenseConfiguration(apiBaseURL: URL(string: "https://license.offsend.io")!)
    #if DEBUG
    public static let develop = LicenseConfiguration(apiBaseURL: URL(string: "http://localhost:3000")!)
    #endif
}

public enum LicenseServiceError: LocalizedError, Equatable {
    case invalidURL
    case transport(String)
    case unexpectedResponse
    case decodingFailed(String)
    case apiError(code: String, message: String)
    case deviceLimitReached(devices: [LicenseActivatedDevice])
    case reauthRequired(String)

    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid API URL."
        case .transport(let message):
            return message
        case .unexpectedResponse:
            return "Unexpected response from license server."
        case .decodingFailed(let message):
            return message
        case .apiError(_, let message):
            return message
        case .deviceLimitReached:
            return "Your device limit has been reached."
        case .reauthRequired(let message):
            return message
        }
    }
}

public struct LicenseActivatedDevice: Codable, Equatable, Sendable {
    public var activationId: String
    public var deviceName: String?
    public var lastSeenAt: Date?

    public init(activationId: String, deviceName: String? = nil, lastSeenAt: Date? = nil) {
        self.activationId = activationId
        self.deviceName = deviceName
        self.lastSeenAt = lastSeenAt
    }

    enum CodingKeys: String, CodingKey {
        case activationId = "activation_id"
        case deviceName = "device_name"
        case lastSeenAt = "last_seen_at"
    }
}

public struct LicenseVerifySuccess: Equatable, Sendable {
    public var licenseToken: String
    public var plan: String
    public var deviceLimit: Int?
    public var expiresAt: Date?
    public var graceUntil: Date?

    public init(
        licenseToken: String,
        plan: String,
        deviceLimit: Int? = nil,
        expiresAt: Date? = nil,
        graceUntil: Date? = nil
    ) {
        self.licenseToken = licenseToken
        self.plan = plan
        self.deviceLimit = deviceLimit
        self.expiresAt = expiresAt
        self.graceUntil = graceUntil
    }
}

public struct LicenseValidateResult: Equatable, Sendable {
    public var licenseToken: String?
    public var licenseStatus: String
    public var billingState: String
    public var expiresAt: Date?
    public var graceUntil: Date?

    public init(
        licenseToken: String?,
        licenseStatus: String,
        billingState: String,
        expiresAt: Date? = nil,
        graceUntil: Date? = nil
    ) {
        self.licenseToken = licenseToken
        self.licenseStatus = licenseStatus
        self.billingState = billingState
        self.expiresAt = expiresAt
        self.graceUntil = graceUntil
    }
}

struct CheckoutCreateRequest: Encodable {
    var email: String?
    var planId: String

    enum CodingKeys: String, CodingKey {
        case email
        case planId = "plan_id"
    }
}

struct CheckoutCreateResponse: Decodable {
    var status: String
    var checkoutUrl: String?

    enum CodingKeys: String, CodingKey {
        case status
        case checkoutUrl = "checkout_url"
    }
}

struct ActivationRequestCodeRequest: Encodable {
    var email: String
}

struct ActivationRequestCodeResponse: Decodable {
    var status: String
    var message: String?
}

struct ActivationVerifyCodeRequest: Encodable {
    var email: String
    var code: String
    var deviceId: String
    var deviceName: String?
    var appVersion: String
    var osVersion: String

    enum CodingKeys: String, CodingKey {
        case email
        case code
        case deviceId = "device_id"
        case deviceName = "device_name"
        case appVersion = "app_version"
        case osVersion = "os_version"
    }
}

struct ActivationVerifyCodeEnvelope: Decodable {
    var status: String
    var licenseToken: String?
    var plan: String?
    var deviceLimit: Int?
    var expiresAt: Date?
    var graceUntil: Date?
    var code: String?
    var message: String?
    var devices: [LicenseActivatedDevice]?

    enum CodingKeys: String, CodingKey {
        case status
        case licenseToken = "license_token"
        case plan
        case deviceLimit = "device_limit"
        case expiresAt = "expires_at"
        case graceUntil = "grace_until"
        case code
        case message
        case devices
    }
}

struct LicenseValidateRequest: Encodable {
    var licenseToken: String
    var deviceId: String
    var appVersion: String

    enum CodingKeys: String, CodingKey {
        case licenseToken = "license_token"
        case deviceId = "device_id"
        case appVersion = "app_version"
    }
}

struct LicenseValidateEnvelope: Decodable {
    var status: String
    var licenseToken: String?
    var licenseStatus: String?
    var billingState: String?
    var expiresAt: Date?
    var graceUntil: Date?

    enum CodingKeys: String, CodingKey {
        case status
        case licenseToken = "license_token"
        case licenseStatus = "license_status"
        case billingState = "billing_state"
        case expiresAt = "expires_at"
        case graceUntil = "grace_until"
    }
}

struct BillingPortalEnvelope: Decodable {
    var status: String
    var portalUrl: String?
    var message: String?

    enum CodingKeys: String, CodingKey {
        case status
        case portalUrl = "portal_url"
        case message
    }
}
