import Foundation

public enum EnvironmentPoisoningRisk: String, Equatable, Sendable {
    case confirm
    case deny
}

public struct EnvironmentPoisoningMatch: Equatable, Sendable {
    public let variable: String
    public let risk: EnvironmentPoisoningRisk
    public let reason: String

    public init(variable: String, risk: EnvironmentPoisoningRisk, reason: String) {
        self.variable = variable
        self.risk = risk
        self.reason = reason
    }
}

/// Recognizes static environment overrides that can redirect executable lookup,
/// dynamic loading, Git helpers/configuration, or interpreter startup.
public enum EnvironmentPoisoningClassifier {
    public static func classify(command: String, cwd: String? = nil) -> EnvironmentPoisoningMatch? {
        for invocation in ShellInvocationExtractor.invocations(in: command) {
            let assignments = invocation.assignments + explicitAssignments(in: invocation.arguments)
            for assignment in assignments {
                if let match = classify(name: assignment.name, value: assignment.value, cwd: cwd) {
                    return match
                }
            }
        }
        return nil
    }

    static func classify(name rawName: String, value: String, cwd: String?) -> EnvironmentPoisoningMatch? {
        let name = rawName.uppercased()
        if name == "PATH" {
            let unsafe = unsafeSearchPath(value, cwd: cwd)
            return EnvironmentPoisoningMatch(
                variable: name,
                risk: unsafe ? .deny : .confirm,
                reason: unsafe
                    ? "PATH includes a relative, workspace, or temporary writable location"
                    : "PATH changes executable resolution"
            )
        }
        if name.hasPrefix("DYLD_") || name.hasPrefix("LD_") {
            return deny(name, "dynamic-loader environment can inject host-process code")
        }
        // Exported shell functions are executed by every child bash.
        if name.hasPrefix("BASH_FUNC_") {
            return deny(name, "exported shell function runs in every child shell")
        }
        if hardDenyVariables.contains(name) {
            return deny(name, "environment can redirect executable configuration or startup code")
        }
        if isExecutionSensitiveGitVariable(name) {
            return deny(name, "Git environment can redirect helpers, config, or executable lookup")
        }
        if helperProgramVariables.contains(name) {
            let unsafe = unsafeHelperProgram(value, cwd: cwd)
            return EnvironmentPoisoningMatch(
                variable: name,
                risk: unsafe ? .deny : .confirm,
                reason: unsafe
                    ? "helper program is a shell fragment or lives in a relative, workspace, or temporary writable location"
                    : "helper program is launched by other tools on this host"
            )
        }
        if ["HOME", "XDG_CONFIG_HOME"].contains(name) {
            let unsafe = unsafeSinglePath(value, cwd: cwd)
            return EnvironmentPoisoningMatch(
                variable: name,
                risk: unsafe ? .deny : .confirm,
                reason: unsafe
                    ? "configuration home points to a relative, workspace, or temporary writable location"
                    : "configuration home changes which trusted files tools load"
            )
        }
        return nil
    }

    /// Commands whose whole purpose is to set environment. Prefix assignments and
    /// `env VAR=…` are already attached to the invocation by the extractor.
    private static func explicitAssignments(in arguments: [String]) -> [ShellAssignment] {
        guard let executable = arguments.first.map(ShellInvocationExtractor.executableName) else {
            return []
        }
        if ["export", "declare", "typeset", "setenv"].contains(executable) {
            if executable == "setenv", arguments.count >= 3, arguments[1].firstIndex(of: "=") == nil {
                return [ShellAssignment(name: arguments[1], value: arguments[2])]
            }
            return arguments.dropFirst().compactMap(ShellInvocationExtractor.assignment)
        }
        if executable == "launchctl", arguments.count >= 4, arguments[1] == "setenv" {
            return [ShellAssignment(name: arguments[2], value: arguments[3])]
        }
        return []
    }

    private static func isExecutionSensitiveGitVariable(_ name: String) -> Bool {
        if name.hasPrefix("GIT_CONFIG_") { return true }
        return [
            "GIT_EXEC_PATH",
            "GIT_TEMPLATE_DIR",
            "GIT_SSH",
            "GIT_SSH_COMMAND",
            "GIT_ASKPASS",
            "GIT_EDITOR",
            "GIT_SEQUENCE_EDITOR",
            "GIT_PAGER",
            "GIT_DIR",
            "GIT_COMMON_DIR",
            "GIT_WORK_TREE",
            "GIT_OBJECT_DIRECTORY",
            "GIT_ALTERNATE_OBJECT_DIRECTORIES",
            "GIT_PROTOCOL_FROM_USER",
            "GIT_ALLOW_PROTOCOL",
        ].contains(name)
    }

    /// A helper program is either a plain executable the user already trusts or a
    /// command line. Only the latter — and anything resolving into agent-writable
    /// space — is worth a hard deny.
    private static func unsafeHelperProgram(_ value: String, cwd: String?) -> Bool {
        if value.contains(where: { ";|&`$(){}<>\n".contains($0) }) { return true }
        let words = value.split(whereSeparator: \.isWhitespace).map(String.init)
        guard let program = words.first else { return false }
        // `EDITOR="code --wait"` is ordinary; `EDITOR="sh -c payload"` is not.
        if words.dropFirst().contains(where: { $0.hasPrefix("-") && $0.dropFirst().contains("c") }) {
            return true
        }
        guard program.contains("/") else { return false }
        return unsafeSinglePath(program, cwd: cwd)
    }

    private static func unsafeSearchPath(_ value: String, cwd: String?) -> Bool {
        value.split(separator: ":", omittingEmptySubsequences: false).contains { component in
            let path = String(component)
            if ["$PATH", "${PATH}"].contains(path) { return false }
            return unsafeSinglePath(path, cwd: cwd)
        }
    }

    private static func unsafeSinglePath(_ value: String, cwd: String?) -> Bool {
        let path = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if path.isEmpty || path == "." || path == ".." { return true }
        if path.hasPrefix("$PWD") || path.hasPrefix("${PWD}") { return true }
        if path.hasPrefix("/tmp")
            || path.hasPrefix("/var/tmp")
            || path.hasPrefix("/private/tmp") {
            return true
        }
        if let cwd {
            let root = URL(fileURLWithPath: cwd).standardizedFileURL.path
            let resolved = URL(
                fileURLWithPath: PromptReadGate.resolveFilesystemPath(path, cwd: cwd)
            ).standardizedFileURL.path
            if resolved == root || resolved.hasPrefix(root + "/") { return true }
        }
        if path.hasPrefix("$") || path.hasPrefix("~") { return false }
        return !path.hasPrefix("/")
    }

    private static func deny(_ variable: String, _ reason: String) -> EnvironmentPoisoningMatch {
        EnvironmentPoisoningMatch(variable: variable, risk: .deny, reason: reason)
    }

    /// Variables that name a program another tool launches. Judged by value,
    /// because setting them to a normal editor or pager is routine.
    private static let helperProgramVariables: Set<String> = [
        "EDITOR",
        "VISUAL",
        "PAGER",
        "MANPAGER",
        "DIFFPROG",
        "SHELL",
        "LESSOPEN",
        "LESSCLOSE",
    ]

    private static let hardDenyVariables: Set<String> = [
        "BASH_ENV",
        "ENV",
        "ZDOTDIR",
        "IFS",
        "CDPATH",
        "SHELLOPTS",
        "NODE_OPTIONS",
        "NODE_REPL_EXTERNAL_MODULE",
        "NODE_PATH",
        "PYTHONPATH",
        "PYTHONSTARTUP",
        "PYTHONHOME",
        "PYTHONEXECUTABLE",
        "PYTHONUSERBASE",
        "RUBYOPT",
        "RUBYLIB",
        "GEM_HOME",
        "GEM_PATH",
        "PERL5OPT",
        "PERL5LIB",
        "JAVA_TOOL_OPTIONS",
        "JDK_JAVA_OPTIONS",
        "_JAVA_OPTIONS",
        "CLASSPATH",
        "SSH_ASKPASS",
        "SUDO_ASKPASS",
    ]
}
