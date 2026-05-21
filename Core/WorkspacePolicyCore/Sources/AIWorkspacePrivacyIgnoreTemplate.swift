import Foundation

public enum AIWorkspacePrivacyIgnoreTemplate {
    public static let defaultPatterns: [String] = [
        ".env*",
        "*.pem",
        "*.key",
        ".ssh/",
        ".aws/",
        "credentials.json",
        "secrets.json"
    ]

    public static var contents: String {
        ([IgnoreFileParser.defaultHeader] + defaultPatterns).joined(separator: "\n") + "\n"
    }
}
