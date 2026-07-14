import Foundation

public enum PromptHookInputError: Error, Equatable, LocalizedError {
    case invalidJSON
    case missingPrompt(adapter: CheckHookAdapter)

    public var errorDescription: String? {
        switch self {
        case .invalidJSON:
            return "Hook stdin is not valid JSON."
        case .missingPrompt(let adapter):
            return "Hook JSON is missing the prompt field for adapter '\(adapter.rawValue)'."
        }
    }
}

public struct PromptHookPayload: Equatable, Sendable {
    public let prompt: String
    public let attachmentPaths: [String]

    public init(prompt: String, attachmentPaths: [String] = []) {
        self.prompt = prompt
        self.attachmentPaths = attachmentPaths
    }
}

/// Extracts the user prompt text from AI-editor hook stdin JSON.
public enum PromptHookInput {
    public static func prompt(fromJSON json: String, adapter: CheckHookAdapter) throws -> String {
        try payload(fromJSON: json, adapter: adapter).prompt
    }

    public static func payload(fromJSON json: String, adapter: CheckHookAdapter) throws -> PromptHookPayload {
        guard let data = json.data(using: .utf8) else {
            throw PromptHookInputError.invalidJSON
        }
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw PromptHookInputError.invalidJSON
        }
        guard let root = object as? [String: Any] else {
            throw PromptHookInputError.invalidJSON
        }

        let prompt: String?
        switch adapter {
        case .cursor, .claude, .codex:
            prompt = root["prompt"] as? String
        case .windsurf:
            let toolInfo = root["tool_info"] as? [String: Any]
            prompt = toolInfo?["user_prompt"] as? String
        }

        guard let prompt else {
            throw PromptHookInputError.missingPrompt(adapter: adapter)
        }
        return PromptHookPayload(
            prompt: prompt,
            attachmentPaths: attachmentPaths(from: root)
        )
    }

    /// Cursor-style `attachments: [{type, file_path|filePath}]`.
    public static func attachmentPaths(from root: [String: Any]) -> [String] {
        guard let attachments = root["attachments"] as? [[String: Any]] else {
            return []
        }
        return attachments.compactMap { item in
            if let path = item["file_path"] as? String, !path.isEmpty { return path }
            if let path = item["filePath"] as? String, !path.isEmpty { return path }
            return nil
        }
    }
}

/// Path heuristics for prompt attachments and read-gates (warn/deny only — files are not opened).
public enum PromptAttachmentAdvisor {
    /// Basename tokens matched only with an exact name or a separator (`.`, `-`, `_`).
    private static let sensitiveBasenames = [
        "credentials", "secrets", "id_rsa", "id_ed25519", "id_ecdsa",
        "kubeconfig", "serviceaccountkey",
    ]

    private static let sensitiveExactFiles = [
        "google-services.json", "googleservice-info.plist",
    ]

    private static let sensitiveDotfiles = [
        ".npmrc", ".pypirc", ".netrc",
    ]

    private static let sensitiveExtensions = [
        "pem", "p12", "pfx", "p8", "kdbx", "ovpn", "rdp",
        "tfstate", "tfvars", "jks", "keystore", "mobileprovision",
    ]

    private static let sensitiveDirectoryComponents: Set<String> = [
        ".ssh", ".aws", ".azure", ".kube", ".docker", ".gnupg", ".fly",
    ]

    public static func suspiciousPaths(in paths: [String]) -> [String] {
        paths.filter(isSuspicious(path:))
    }

    public static func isSuspicious(path: String) -> Bool {
        let components = path
            .replacingOccurrences(of: "\\", with: "/")
            .lowercased()
            .split(separator: "/")
            .map(String.init)
        if components.contains(where: sensitiveDirectoryComponents.contains) {
            return true
        }

        let name = URL(fileURLWithPath: path).lastPathComponent.lowercased()

        if name == ".env" || name.hasPrefix(".env.") || name.hasSuffix(".env") {
            return true
        }
        if sensitiveDotfiles.contains(name) {
            return true
        }
        if sensitiveExactFiles.contains(name) {
            return true
        }
        if sensitiveBasenames.contains(where: { basenameMatches($0, name: name) }) {
            return true
        }
        // Private key material often named `*.key` / `*.pem`.
        if let ext = fileExtension(of: name), sensitiveExtensions.contains(ext) || ext == "key" {
            return true
        }
        return false
    }

    public static func adviceLines(for paths: [String]) -> [String] {
        suspiciousPaths(in: paths).map { path in
            let name = URL(fileURLWithPath: path).lastPathComponent
            return "attachment (\(name)): do not attach secret files; add to AI ignore (`offsend prepare`)."
        }
    }

    /// `credentials.json` / `credentials-prod` match; `CredentialsForm.tsx` does not.
    private static func basenameMatches(_ marker: String, name: String) -> Bool {
        if name == marker { return true }
        if name.hasPrefix(marker + ".") { return true }
        if name.hasPrefix(marker + "-") { return true }
        if name.hasPrefix(marker + "_") { return true }
        return false
    }

    private static func fileExtension(of name: String) -> String? {
        guard let dot = name.lastIndex(of: "."), dot != name.startIndex else { return nil }
        return String(name[name.index(after: dot)...])
    }
}
