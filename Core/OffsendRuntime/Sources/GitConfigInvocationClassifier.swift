import Foundation

public struct GitConfigInvocationMatch: Equatable, Sendable {
    public let key: String
    public let operation: String

    public init(key: String, operation: String) {
        self.key = key
        self.operation = operation
    }
}

/// Recognizes static `git config` mutations and per-invocation `git -c`
/// overrides that can cause Git to execute workspace- or agent-controlled code.
/// Dynamic shell construction (`eval`, variables, generated scripts) remains
/// outside this classifier and is reported as a residual shell-gate gap.
public enum GitConfigInvocationClassifier {
    public static func classify(command: String) -> GitConfigInvocationMatch? {
        for invocation in ShellInvocationExtractor.invocations(in: command)
        where invocation.executableName == "git" {
            if let match = classifyGitInvocation(invocation.arguments) {
                return match
            }
        }
        return nil
    }

    static func isExecutionSensitiveKey(_ rawKey: String) -> Bool {
        let key = normalizeKey(rawKey)
        if [
            "core.hookspath",
            "core.sshcommand",
            "core.gitproxy",
            "core.fsmonitor",
            "core.editor",
            "core.pager",
            "core.askpass",
            "core.alternaterefscommand",
            "init.templatedir",
            "sequence.editor",
            "diff.external",
            "gpg.program",
            "include.path",
            "credential.helper",
            "uploadpack.packobjectshook",
            "web.browser",
        ].contains(key) {
            return true
        }
        if key.hasPrefix("alias.") || key.hasPrefix("pager.") {
            return true
        }
        if key.hasPrefix("includeif.") && key.hasSuffix(".path") {
            return true
        }
        let parts = key.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 3 else { return false }
        if parts.first == "credential", parts.last == "helper" { return true }
        if parts.first == "diff", ["command", "textconv"].contains(parts.last ?? "") { return true }
        if parts.first == "merge", parts.last == "driver" { return true }
        if parts.first == "filter", ["clean", "smudge", "process"].contains(parts.last ?? "") {
            return true
        }
        if parts.first == "gpg", parts.last == "program" { return true }
        if parts.first == "submodule", parts.last == "update" { return true }
        if ["difftool", "mergetool", "guitool", "man", "browser"].contains(String(parts.first ?? "")),
           parts.last == "cmd" || parts.last == "path" {
            return true
        }
        if parts.first == "trailer", parts.last == "command" { return true }
        // `protocol.ext.allow` re-enables `ext::sh -c …` remote helpers.
        if parts.first == "protocol", parts.last == "allow" { return true }
        if parts.first == "remote",
           ["uploadpack", "receivepack", "vcs"].contains(parts.last ?? "") {
            return true
        }
        return false
    }

    private static func classifyGitInvocation(_ tokens: [String]) -> GitConfigInvocationMatch? {
        guard tokens.count > 1 else { return nil }
        var index = 1
        while index < tokens.count {
            let token = tokens[index]
            if token == "-c" {
                guard index + 1 < tokens.count else { return nil }
                if let key = assignmentKey(tokens[index + 1]), isExecutionSensitiveKey(key) {
                    return GitConfigInvocationMatch(key: key, operation: "invocation override")
                }
                index += 2
                continue
            }
            if token.hasPrefix("-c"), token.count > 2 {
                let assignment = String(token.dropFirst(2))
                if let key = assignmentKey(assignment), isExecutionSensitiveKey(key) {
                    return GitConfigInvocationMatch(key: key, operation: "invocation override")
                }
                index += 1
                continue
            }
            if token == "--config-env" {
                guard index + 1 < tokens.count else { return nil }
                if let key = assignmentKey(tokens[index + 1]), isExecutionSensitiveKey(key) {
                    return GitConfigInvocationMatch(key: key, operation: "environment override")
                }
                index += 2
                continue
            }
            if token.hasPrefix("--config-env=") {
                let assignment = String(token.dropFirst("--config-env=".count))
                if let key = assignmentKey(assignment), isExecutionSensitiveKey(key) {
                    return GitConfigInvocationMatch(key: key, operation: "environment override")
                }
                index += 1
                continue
            }
            if token.hasPrefix("--exec-path=") {
                return GitConfigInvocationMatch(key: "git.execpath", operation: "invocation override")
            }
            if token == "config" {
                return classifyConfigArguments(Array(tokens.dropFirst(index + 1)))
            }
            if ["-C", "--git-dir", "--work-tree", "--namespace", "--super-prefix"]
                .contains(token) {
                index += 2
                continue
            }
            if token.hasPrefix("-") {
                index += 1
                continue
            }
            return nil
        }
        return nil
    }

    private static func classifyConfigArguments(_ arguments: [String]) -> GitConfigInvocationMatch? {
        var mutation: String?
        var positionals: [String] = []
        var index = 0
        while index < arguments.count {
            let token = arguments[index]
            if token == "edit" || token == "--edit" || token == "-e" {
                return GitConfigInvocationMatch(key: "core.editor", operation: "edit")
            }
            if ["get", "get-all", "get-regexp", "get-urlmatch", "list"].contains(token) {
                return nil
            }
            if ["set", "unset", "unset-all", "rename-section", "remove-section"]
                .contains(token) {
                mutation = token
                index += 1
                continue
            }
            if ["--get", "--get-all", "--get-regexp", "--get-urlmatch", "--list", "-l"]
                .contains(token) {
                return nil
            }
            if ["--add", "--replace-all", "--unset", "--unset-all", "--rename-section", "--remove-section"]
                .contains(token) {
                mutation = String(token.dropFirst(2))
                index += 1
                continue
            }
            if ["--file", "-f", "--type", "--comment"].contains(token) {
                index += 2
                continue
            }
            if token.hasPrefix("-") {
                index += 1
                continue
            }
            positionals.append(token)
            index += 1
        }

        if mutation == "rename-section" || mutation == "remove-section" {
            for section in positionals.prefix(mutation == "rename-section" ? 2 : 1)
                where isExecutionSensitiveSection(section) {
                return GitConfigInvocationMatch(key: section, operation: mutation ?? "mutation")
            }
            return nil
        }
        guard let key = positionals.first else { return nil }
        let isMutation = mutation != nil || positionals.count >= 2
        guard isMutation, isExecutionSensitiveKey(key) else { return nil }
        return GitConfigInvocationMatch(key: normalizeKey(key), operation: mutation ?? "set")
    }

    private static func assignmentKey(_ assignment: String) -> String? {
        guard let equals = assignment.firstIndex(of: "="), equals != assignment.startIndex else {
            return nil
        }
        return normalizeKey(String(assignment[..<equals]))
    }

    private static func isExecutionSensitiveSection(_ rawSection: String) -> Bool {
        let section = rawSection.lowercased()
        return [
            "alias", "credential", "diff", "merge", "filter", "pager",
            "include", "includeif", "gpg", "submodule",
            "difftool", "mergetool", "guitool", "trailer",
        ].contains { section == $0 || section.hasPrefix($0 + ".") }
    }

    private static func normalizeKey(_ key: String) -> String {
        key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

}
