import Foundation

public enum AIWorkspacePrivacyIgnoreTemplate {
    public static let defaultPatterns: [String] = [
        ".env*",
        "*.pem",
        "*.key",
        ".ssh/",
        ".aws/",
        ".azure/",
        ".kube/",
        ".docker/",
        "credentials.json",
        "secrets.json",
        "service-account*.json",
        "gcp-credentials*.json",
        "azureauth.json",
        "kubeconfig",
        "*.kubeconfig",
        "*.tfstate",
        "*.tfstate.*",
        "*.tfvars",
        "*.p12",
        "*.pfx",
        "*.gpg",
        ".netrc",
        ".npmrc",
        ".pypirc",
        ".htpasswd",
        ".dockerconfigjson",
        "serviceAccountKey.json",
        "firebase-adminsdk-*.json",
        "*.sql.gz",
        "*.dump"
    ]

    public static var contents: String {
        ([IgnoreFileParser.defaultHeader] + defaultPatterns).joined(separator: "\n") + "\n"
    }
}
