import Foundation

/// Reads JWT payload JSON without signature verification (for UI eligibility only).
/// Pro feature gating must rely on `/license/validate` and stored billing dates, not on unverified JWT claims.
public enum LicenseJWTReader {
    public static func payloadJSON(from jwt: String) -> [String: Any]? {
        let parts = jwt.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        let payloadSegment = String(parts[1])
        guard let data = base64URLDecode(payloadSegment) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    public static func hasPortalIdentifiers(in jwt: String) -> Bool {
        guard let json = payloadJSON(from: jwt) else { return false }
        let licenseId = json["license_id"] as? String
        let activationId = json["activation_id"] as? String
        return !(licenseId ?? "").isEmpty && !(activationId ?? "").isEmpty
    }

    private static func base64URLDecode(_ input: String) -> Data? {
        var base64 = input.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        let padding = 4 - base64.count % 4
        if padding < 4 {
            base64 += String(repeating: "=", count: padding)
        }
        return Data(base64Encoded: base64)
    }
}
