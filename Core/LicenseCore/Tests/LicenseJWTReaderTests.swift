import Foundation
import XCTest

import LicenseCore

final class LicenseJWTReaderTests: XCTestCase {
    func testHasPortalIdentifiersWhenPayloadContainsIds() {
        let payload: [String: String] = ["license_id": "lic_test", "activation_id": "act_test"]
        let data = try! JSONSerialization.data(withJSONObject: payload)
        let mid = data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        let jwt = "hdr.\(mid).sig"
        XCTAssertTrue(LicenseJWTReader.hasPortalIdentifiers(in: jwt))
    }

    func testHasPortalIdentifiersFalseWhenMissing() {
        let payload: [String: String] = ["license_id": "lic_only"]
        let data = try! JSONSerialization.data(withJSONObject: payload)
        let mid = data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        let jwt = "hdr.\(mid).sig"
        XCTAssertFalse(LicenseJWTReader.hasPortalIdentifiers(in: jwt))
    }
}

final class LicenseOfflineEntitlementTests: XCTestCase {
    func testGraceAfterExpiry() {
        let exp = Date(timeIntervalSince1970: 1_000)
        let grace = Date(timeIntervalSince1970: 2_000)
        let mid = Date(timeIntervalSince1970: 1_500)
        XCTAssertEqual(LicenseOfflineEntitlement.resolve(expiresAt: exp, graceUntil: grace, now: mid), .proGrace)
    }
}
