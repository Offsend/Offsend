import Foundation

public enum NERLabelMapper {
    private static let defaultMap: [String: SensitiveEntityType] = [
        "PERSON": .personName,
        "PER": .personName,
        "GIVENNAME": .personName,
        "SURNAME": .personName,
        "TITLE": .personName,
        "NAME": .personName,
        "ORG": .customCompany,
        "ORGANIZATION": .customCompany,
        "EMAIL": .email,
        "TELEPHONENUM": .phone,
        "PHONE": .phone,
        "CREDITCARDNUMBER": .creditCardLike,
        "CITY": .streetAddress,
        "STREET": .streetAddress,
        "ADDRESS": .streetAddress,
        "LOCATION": .streetAddress,
        "LOC": .streetAddress,
        "SOCIALNUM": .governmentId,
        "PASSPORTNUM": .governmentId,
        "SSN": .governmentId,
        "MISC": .customSensitiveTerm,
    ]

    public static func defaultEntityType(for label: String) -> SensitiveEntityType? {
        defaultMap[normalize(label)]
    }

    /// Uppercases and strips a leading BIO/BIOES prefix only; replacing `B-`/`I-` anywhere
    /// in the string would mangle labels like `SUB-NAME`.
    private static func normalize(_ label: String) -> String {
        let uppercased = label.uppercased()
        for prefix in ["B-", "I-", "E-", "S-", "B_", "I_"] where uppercased.hasPrefix(prefix) {
            return String(uppercased.dropFirst(prefix.count))
        }
        return uppercased
    }
}
