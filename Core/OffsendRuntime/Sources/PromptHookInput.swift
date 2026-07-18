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
    /// Editor working directory from hook JSON (`cwd`), when present.
    public let cwd: String?

    public init(prompt: String, attachmentPaths: [String] = [], cwd: String? = nil) {
        self.prompt = prompt
        self.attachmentPaths = attachmentPaths
        self.cwd = cwd
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
        let attachments = attachmentPaths(from: root)
        let mentions = mentionPaths(in: prompt)
        var paths: [String] = []
        var seen = Set<String>()
        for path in attachments + mentions {
            if seen.insert(path).inserted {
                paths.append(path)
            }
        }
        let cwd = (root["cwd"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        return PromptHookPayload(
            prompt: prompt,
            attachmentPaths: paths,
            cwd: cwd
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

    /// File-like `@mentions` in the prompt (`@index.js`, `@src/a.ts`). Skips emails (`a@b.co`).
    public static func mentionPaths(in prompt: String) -> [String] {
        let pattern = #"(?<![\w.-])@((?:(?:\./|\.\./|/)[\w./+-]+)|(?:[\w.-]+/[\w./+-]+)|(?:[\w.-]+\.[A-Za-z0-9]{1,12}))"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(prompt.startIndex..<prompt.endIndex, in: prompt)
        return regex.matches(in: prompt, range: range).compactMap { match in
            guard match.numberOfRanges >= 2,
                  let pathRange = Range(match.range(at: 1), in: prompt) else { return nil }
            let path = String(prompt[pathRange])
            return path.isEmpty ? nil : path
        }
    }
}

/// Path heuristics for prompt attachments and read-gates (path deny / warn).
/// Read-gate may also scan file content (hook payload or a bounded disk prefix).
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
            return "attachment (\(name)): do not attach secret files; add to AI ignore (`offsend protect`)."
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
