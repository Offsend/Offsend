import Foundation

/// High-level license API aligned with Offsend backend MVP (`/docs/description.md`).
public final class LicenseService: @unchecked Sendable {
    private let configuration: LicenseConfiguration
    private let api: LicenseAPIClienting
    private let keychain: LicenseKeychainStore
    private let decoder: JSONDecoder

    private let pricingCache: LicensePricingCacheStore

    public init(
        configuration: LicenseConfiguration = .production,
        api: LicenseAPIClienting? = nil,
        keychain: LicenseKeychainStore = LicenseKeychainStore(),
        pricingCache: LicensePricingCacheStore = LicensePricingCacheStore()
    ) {
        self.configuration = configuration
        self.api = api ?? LicenseAPIClient(configuration: configuration)
        self.keychain = keychain
        self.pricingCache = pricingCache
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    /// Loads `/pricing` with TTL cache; on failure uses last cached catalog if any, otherwise `fallback` copy (no concrete price).
    public func loadPricingPresentation(
        appVersion: String,
        localeIdentifier: String?,
        currencyCode: String?,
        fallback: LicensePricingFallbackStrings
    ) async -> LicensePricingPresentation {
        let defaultPlanFallback = configuration.checkoutPlanId
        let now = Date()

        if let cached = pricingCache.load(),
           cached.catalog.status == "ok",
           !cached.catalog.plans.isEmpty {
            let ttl = max(60, cached.ttlSeconds)
            if now.timeIntervalSince(cached.fetchedAt) < TimeInterval(ttl) {
                return LicensePricingPresentation.fromCatalog(cached.catalog, defaultPlanIdFallback: defaultPlanFallback)
            }
        }

        var query: [URLQueryItem] = [
            URLQueryItem(name: "platform", value: "macos"),
            URLQueryItem(name: "app_version", value: appVersion)
        ]
        if let localeIdentifier, !localeIdentifier.isEmpty {
            query.append(URLQueryItem(name: "locale", value: localeIdentifier))
        }
        if let currencyCode, !currencyCode.isEmpty {
            query.append(URLQueryItem(name: "currency", value: currencyCode))
        }

        do {
            let data = try await api.getJSON(path: "/pricing", queryItems: query)
            let catalog = try decoder.decode(LicensePricingCatalog.self, from: data)
            guard catalog.status == "ok", !catalog.plans.isEmpty else {
                throw LicenseServiceError.unexpectedResponse
            }
            let ttl = max(60, catalog.cacheTtlSeconds ?? 3600)
            try? pricingCache.save(LicensePricingCachedEnvelope(fetchedAt: now, ttlSeconds: ttl, catalog: catalog))
            return LicensePricingPresentation.fromCatalog(catalog, defaultPlanIdFallback: defaultPlanFallback)
        } catch {
            if let cached = pricingCache.load(), cached.catalog.status == "ok", !cached.catalog.plans.isEmpty {
                return LicensePricingPresentation.fromCatalog(cached.catalog, defaultPlanIdFallback: defaultPlanFallback)
            }
            return LicensePricingPresentation.fallback(fallback, defaultPlanId: defaultPlanFallback)
        }
    }

    /// Returns existing device id from Keychain or creates and persists a new one.
    public func deviceId() throws -> UUID {
        if let existing = try keychain.load() {
            return existing.deviceId
        }
        let created = LicenseKeychainSecrets(deviceId: UUID())
        try keychain.save(created)
        return created.deviceId
    }

    public func storedLicenseToken() throws -> String? {
        try keychain.load()?.signedLicenseToken
    }

    public func canOpenBillingPortal() throws -> Bool {
        guard let token = try storedLicenseToken(), !token.isEmpty else { return false }
        return LicenseJWTReader.hasPortalIdentifiers(in: token)
    }

    public func requestActivationCode(email: String) async throws {
        let body = ActivationRequestCodeRequest(email: email)
        _ = try await api.postJSON(path: "/activation/request-code", body: body, bearerToken: nil)
    }

    public func verifyActivationCode(
        email: String,
        code: String,
        deviceName: String?,
        appVersion: String,
        osVersion: String
    ) async throws -> LicenseVerifySuccess {
        let deviceUUID = try deviceId()
        let body = ActivationVerifyCodeRequest(
            email: email,
            code: code,
            deviceId: deviceUUID.uuidString,
            deviceName: deviceName,
            appVersion: appVersion,
            osVersion: osVersion
        )
        let data = try await api.postJSON(path: "/activation/verify-code", body: body, bearerToken: nil)
        let envelope = try decoder.decode(ActivationVerifyCodeEnvelope.self, from: data)
        guard envelope.status == "ok" else {
            if envelope.code == "DEVICE_LIMIT_REACHED" {
                throw LicenseServiceError.deviceLimitReached(devices: envelope.devices ?? [])
            }
            throw LicenseServiceError.apiError(
                code: envelope.code ?? "error",
                message: envelope.message ?? "Activation failed."
            )
        }
        // offsend:ignore-next-line
        guard let token = envelope.licenseToken, !token.isEmpty else {
            throw LicenseServiceError.unexpectedResponse
        }
        return LicenseVerifySuccess(
            licenseToken: token,
            plan: envelope.plan ?? "pro",
            deviceLimit: envelope.deviceLimit,
            expiresAt: envelope.expiresAt,
            graceUntil: envelope.graceUntil
        )
    }

    public func validateLicense(appVersion: String) async throws -> LicenseValidateResult {
        // offsend:ignore-next-line
        guard var secrets = try keychain.load(), let token = secrets.signedLicenseToken, !token.isEmpty else {
            throw LicenseServiceError.apiError(code: "no_token", message: "No license on this device.")
        }
        let body = LicenseValidateRequest(
            licenseToken: token,
            deviceId: secrets.deviceId.uuidString,
            appVersion: appVersion
        )
        let data = try await api.postJSON(path: "/license/validate", body: body, bearerToken: nil)
        let envelope = try decoder.decode(LicenseValidateEnvelope.self, from: data)
        guard envelope.status == "ok" else {
            throw LicenseServiceError.unexpectedResponse
        }
        if let newToken = envelope.licenseToken, !newToken.isEmpty {
            secrets.signedLicenseToken = newToken
        }
        secrets.lastValidationAt = Date()
        try keychain.save(secrets)
        return LicenseValidateResult(
            licenseToken: envelope.licenseToken,
            licenseStatus: envelope.licenseStatus ?? "inactive",
            billingState: envelope.billingState ?? "expired",
            expiresAt: envelope.expiresAt,
            graceUntil: envelope.graceUntil
        )
    }

    public func createCheckout(email: String?, planId: String? = nil) async throws -> URL {
        let plan = planId.flatMap { $0.isEmpty ? nil : $0 } ?? configuration.checkoutPlanId
        let body = CheckoutCreateRequest(email: email, planId: plan)
        let data = try await api.postJSON(path: "/checkout/create", body: body, bearerToken: nil)
        let response = try decoder.decode(CheckoutCreateResponse.self, from: data)
        guard response.status == "ok", let urlString = response.checkoutUrl, let url = URL(string: urlString) else {
            throw LicenseServiceError.unexpectedResponse
        }
        return url
    }

    public func billingPortalURL() async throws -> URL {
        guard let token = try storedLicenseToken(), !token.isEmpty else {
            throw LicenseServiceError.reauthRequired("Please restore your license to manage billing.")
        }
        let data = try await api.postJSON(path: "/billing/portal", body: EmptyBody(), bearerToken: token)
        let envelope = try decoder.decode(BillingPortalEnvelope.self, from: data)
        if envelope.status == "reauth_required" {
            throw LicenseServiceError.reauthRequired(envelope.message ?? "Please restore your license to manage billing.")
        }
        guard envelope.status == "ok", let urlString = envelope.portalUrl, let url = URL(string: urlString) else {
            throw LicenseServiceError.unexpectedResponse
        }
        return url
    }

    public func persistVerifiedLicense(
        token: String,
        lastValidationAt: Date = Date()
    ) throws {
        _ = try deviceId()
        guard var secrets = try keychain.load() else {
            throw LicenseServiceError.unexpectedResponse
        }
        secrets.signedLicenseToken = token
        secrets.lastValidationAt = lastValidationAt
        try keychain.save(secrets)
    }

    public func updateLastValidation(date: Date = Date()) throws {
        guard var secrets = try keychain.load() else { return }
        secrets.lastValidationAt = date
        try keychain.save(secrets)
    }

    public func clearProLicense() throws {
        try keychain.clearLicenseToken()
    }

    public func lastValidationAt() throws -> Date? {
        try keychain.load()?.lastValidationAt
    }
}

private struct EmptyBody: Encodable {}
