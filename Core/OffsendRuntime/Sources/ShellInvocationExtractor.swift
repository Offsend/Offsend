import Foundation

public struct ShellAssignment: Equatable, Sendable {
    public let name: String
    public let value: String

    public init(name: String, value: String) {
        self.name = name
        self.value = value
    }
}

/// One command from a shell line, with leading assignments and launcher
/// wrappers already peeled off.
public struct ShellInvocation: Equatable, Sendable {
    /// Environment applied to this command (`FOO=1 cmd`, `env FOO=1 cmd`).
    public let assignments: [ShellAssignment]
    /// argv of the actual command; empty for a segment that only sets variables.
    public let arguments: [String]

    public init(assignments: [ShellAssignment], arguments: [String]) {
        self.assignments = assignments
        self.arguments = arguments
    }

    public var executableName: String? {
        arguments.first.map(ShellInvocationExtractor.executableName)
    }
}

/// Shared static analysis of an agent shell command: one lexer, one wrapper
/// table, one place that looks inside `sh -c "…"`, interpreter `-c`/`-e`
/// payloads, and `$(…)` bodies.
///
/// This is deliberately not a shell interpreter. `eval`, unresolved `$var`,
/// generated scripts, and environment-array injection stay outside static argv
/// recognition and are reported as residual gaps.
public enum ShellInvocationExtractor {
    /// Nested `-c` scripts are followed this deep; beyond it the payload is
    /// obfuscation rather than a command a person would write.
    static let maxDepth = 4

    private struct Wrapper {
        /// Options that take a separate value argument.
        let valueOptions: Set<String>
        /// Positional arguments before the wrapped command (`timeout 5s cmd`).
        let positionals: Int

        init(valueOptions: Set<String> = [], positionals: Int = 0) {
            self.valueOptions = valueOptions
            self.positionals = positionals
        }
    }

    /// Launchers that run another command, so the interesting argv is further right.
    private static let wrappers: [String: Wrapper] = [
        "env": Wrapper(valueOptions: ["-u", "--unset", "-C", "--chdir"]),
        "command": Wrapper(),
        "exec": Wrapper(valueOptions: ["-a"]),
        "nohup": Wrapper(),
        "setsid": Wrapper(),
        "time": Wrapper(valueOptions: ["-o", "--output", "-f", "--format"]),
        "nice": Wrapper(valueOptions: ["-n", "--adjustment"]),
        "ionice": Wrapper(valueOptions: ["-c", "-n", "-p", "-t"]),
        "stdbuf": Wrapper(valueOptions: ["-i", "-o", "-e", "--input", "--output", "--error"]),
        "timeout": Wrapper(
            valueOptions: ["-s", "--signal", "-k", "--kill-after"],
            positionals: 1
        ),
        "xargs": Wrapper(
            valueOptions: [
                "-I", "-i", "-L", "-n", "-P", "-s", "-d", "-E", "-a",
                "--replace", "--max-lines", "--max-args", "--max-procs",
                "--delimiter", "--arg-file", "--eof",
            ]
        ),
        "sudo": Wrapper(
            valueOptions: [
                "-u", "--user", "-g", "--group", "-h", "--host",
                "-p", "--prompt", "-C", "--chdir", "-R", "--chroot",
                "-T", "--command-timeout",
            ]
        ),
        "doas": Wrapper(valueOptions: ["-u", "-C"]),
    ]

    private static let shellNames: Set<String> = [
        "sh", "bash", "zsh", "dash", "ksh", "mksh", "ash", "busybox",
    ]

    /// Interpreters whose `-c` / `-e` payload is swept for path tokens.
    /// Value is the short option letter (`c` or `e`).
    private static let inlineInterpreterOptions: [String: Character] = [
        "python": "c",
        "python2": "c",
        "python3": "c",
        "pypy": "c",
        "pypy3": "c",
        "node": "e",
        "nodejs": "e",
        "ruby": "e",
        "perl": "e",
        "php": "r",
    ]

    // MARK: - Public API

    public static func invocations(in command: String) -> [ShellInvocation] {
        invocations(in: command, depth: 0)
    }

    /// Every token in the command and in any nested `-c` script, with command
    /// separators removed. Used for path sweeps that do not care about argv
    /// structure.
    public static func allTokens(in command: String) -> [String] {
        var result: [String] = []
        collectTokens(command, depth: 0, into: &result)
        return result
    }

    public static func executableName(_ token: String) -> String {
        token.split(separator: "/").last.map(String.init) ?? token
    }

    // MARK: - Invocations

    private static func invocations(in command: String, depth: Int) -> [ShellInvocation] {
        guard depth <= maxDepth else { return [] }
        return segments(tokens(command)).flatMap { invocations(segment: $0, depth: depth) }
    }

    private static func invocations(segment: [String], depth: Int) -> [ShellInvocation] {
        var index = 0
        var assignments: [ShellAssignment] = []
        while index < segment.count, let assignment = assignment(segment[index]) {
            assignments.append(assignment)
            index += 1
        }

        peel: while index < segment.count {
            let name = executableName(segment[index])
            guard let wrapper = wrappers[name] else { break }
            index += 1
            var positionals = 0
            while index < segment.count {
                let token = segment[index]
                // `command -v git` resolves a path instead of running anything.
                if name == "command", token == "-v" || token == "-V" {
                    return []
                }
                if name == "env", let script = splitStringScript(token, next: segment[safe: index + 1]) {
                    return invocations(in: script, depth: depth + 1)
                }
                if wrapper.valueOptions.contains(token) {
                    index = min(index + 2, segment.count)
                    continue
                }
                if token.hasPrefix("-") {
                    index += 1
                    continue
                }
                if name == "env", let assignment = assignment(token) {
                    assignments.append(assignment)
                    index += 1
                    continue
                }
                if positionals < wrapper.positionals {
                    positionals += 1
                    index += 1
                    continue
                }
                continue peel
            }
            break
        }

        guard index < segment.count else {
            return assignments.isEmpty
                ? []
                : [ShellInvocation(assignments: assignments, arguments: [])]
        }

        let arguments = Array(segment[index...])
        var result = [ShellInvocation(assignments: assignments, arguments: arguments)]
        if let script = inlineScript(in: arguments) {
            // Shell `-c` payloads may contain further shell; interpreter payloads
            // are path-swept via `allTokens` / `nestedScripts` instead.
            if let first = arguments.first, shellNames.contains(executableName(first)) {
                result.append(contentsOf: invocations(in: script, depth: depth + 1))
            }
        }
        return result
    }

    /// The script string of a `sh -c "…"` or `python3 -c "…"` / `node -e "…"`
    /// style invocation, if this argv is one.
    private static func inlineScript(in arguments: [String]) -> String? {
        guard let first = arguments.first else { return nil }
        let name = executableName(first)
        if shellNames.contains(name) {
            return shellInlineScript(in: arguments)
        }
        if let option = inlineInterpreterOptions[name] {
            return interpreterInlineScript(in: arguments, option: option)
        }
        return nil
    }

    private static func shellInlineScript(in arguments: [String]) -> String? {
        var index = 1
        while index < arguments.count {
            let token = arguments[index]
            if token == "-c" {
                return arguments[safe: index + 1]
            }
            if token.hasPrefix("--") {
                index += 1
                continue
            }
            // Combined short options such as `-lc` still take the script next.
            if token.hasPrefix("-") {
                if token.dropFirst().contains("c") {
                    return arguments[safe: index + 1]
                }
                index += 1
                continue
            }
            // A bare positional is a script file, not an inline command.
            return nil
        }
        return nil
    }

    private static func interpreterInlineScript(in arguments: [String], option: Character) -> String? {
        let flag = "-\(option)"
        var index = 1
        while index < arguments.count {
            let token = arguments[index]
            if token == flag {
                return arguments[safe: index + 1]
            }
            // Combined form: `python3 -copen('x')` / `node -econsole.log(1)`.
            if token.hasPrefix(flag), token.count > flag.count {
                return String(token.dropFirst(flag.count))
            }
            if token.hasPrefix("-") {
                index += 1
                continue
            }
            return nil
        }
        return nil
    }

    private static func splitStringScript(_ token: String, next: String?) -> String? {
        if token == "-S" || token == "--split-string" { return next }
        if token.hasPrefix("--split-string=") {
            return String(token.dropFirst("--split-string=".count))
        }
        if token.hasPrefix("-S"), token.count > 2 { return String(token.dropFirst(2)) }
        return nil
    }

    // MARK: - Tokens

    private static func collectTokens(_ command: String, depth: Int, into result: inout [String]) {
        guard depth <= maxDepth else { return }
        let tokens = tokens(command)
        result.append(contentsOf: tokens.filter { !isSeparator($0) })
        for segment in segments(tokens) {
            for script in nestedScripts(in: segment) {
                collectTokens(script, depth: depth + 1, into: &result)
            }
        }
        for body in commandSubstitutionBodies(in: command) {
            collectTokens(body, depth: depth + 1, into: &result)
        }
    }

    /// Bodies of `$(…)` substitutions (best-effort, quote-aware nesting).
    static func commandSubstitutionBodies(in command: String) -> [String] {
        var bodies: [String] = []
        let characters = Array(command)
        var index = 0
        var quote: Character?
        var escaped = false
        while index < characters.count {
            let character = characters[index]
            if escaped {
                escaped = false
                index += 1
                continue
            }
            if character == "\\", quote != "'" {
                escaped = true
                index += 1
                continue
            }
            if let active = quote {
                if character == active { quote = nil }
                index += 1
                continue
            }
            if character == "'" || character == "\"" {
                quote = character
                index += 1
                continue
            }
            if character == "$", index + 1 < characters.count, characters[index + 1] == "(" {
                index += 2
                var depth = 1
                var body = ""
                var innerQuote: Character?
                var innerEscaped = false
                while index < characters.count, depth > 0 {
                    let inner = characters[index]
                    if innerEscaped {
                        body.append(inner)
                        innerEscaped = false
                        index += 1
                        continue
                    }
                    if inner == "\\", innerQuote != "'" {
                        body.append(inner)
                        innerEscaped = true
                        index += 1
                        continue
                    }
                    if let active = innerQuote {
                        body.append(inner)
                        if inner == active { innerQuote = nil }
                        index += 1
                        continue
                    }
                    if inner == "'" || inner == "\"" {
                        innerQuote = inner
                        body.append(inner)
                        index += 1
                        continue
                    }
                    if inner == "(" {
                        depth += 1
                        body.append(inner)
                        index += 1
                        continue
                    }
                    if inner == ")" {
                        depth -= 1
                        if depth == 0 {
                            index += 1
                            break
                        }
                        body.append(inner)
                        index += 1
                        continue
                    }
                    body.append(inner)
                    index += 1
                }
                if !body.isEmpty { bodies.append(body) }
                continue
            }
            index += 1
        }
        return bodies
    }

    /// Script strings anywhere in a segment, so `timeout 5 bash -c '…'` and
    /// `python3 -c '…'` are swept even when not the first token.
    private static func nestedScripts(in segment: [String]) -> [String] {
        var scripts: [String] = []
        var pendingShell = false
        var pendingInterpreter: Character?
        for (index, token) in segment.enumerated() {
            let name = executableName(token)
            if shellNames.contains(name) {
                pendingShell = true
                pendingInterpreter = nil
                continue
            }
            if let option = inlineInterpreterOptions[name] {
                pendingInterpreter = option
                pendingShell = false
                continue
            }
            if let script = splitStringScript(token, next: segment[safe: index + 1]) {
                scripts.append(script)
                continue
            }
            if pendingShell, token.hasPrefix("-"), !token.hasPrefix("--"),
               token.dropFirst().contains("c"), let script = segment[safe: index + 1] {
                scripts.append(script)
                pendingShell = false
                continue
            }
            if let option = pendingInterpreter {
                let flag = "-\(option)"
                if token == flag, let script = segment[safe: index + 1] {
                    scripts.append(script)
                    pendingInterpreter = nil
                    continue
                }
                if token.hasPrefix(flag), token.count > flag.count {
                    scripts.append(String(token.dropFirst(flag.count)))
                    pendingInterpreter = nil
                    continue
                }
                if !token.hasPrefix("-") {
                    pendingInterpreter = nil
                }
            }
            if !token.hasPrefix("-") {
                pendingShell = false
            }
        }
        return scripts
    }

    static func segments(_ tokens: [String]) -> [[String]] {
        var result: [[String]] = []
        var current: [String] = []
        for token in tokens {
            if isSeparator(token) {
                if !current.isEmpty { result.append(current) }
                current = []
            } else {
                current.append(token)
            }
        }
        if !current.isEmpty { result.append(current) }
        return result
    }

    private static func isSeparator(_ token: String) -> Bool {
        [";", "&&", "||", "|", "&", "\n"].contains(token)
    }

    static func assignment(_ token: String) -> ShellAssignment? {
        guard let equals = token.firstIndex(of: "="), equals != token.startIndex else {
            return nil
        }
        let name = String(token[..<equals])
        guard let first = name.first, first == "_" || first.isLetter,
              name.dropFirst().allSatisfy({ $0 == "_" || $0.isLetter || $0.isNumber }) else {
            return nil
        }
        return ShellAssignment(name: name, value: String(token[token.index(after: equals)...]))
    }

    /// Small shell lexer sufficient for static argv recognition. Quotes are
    /// removed while separators outside quotes become standalone tokens.
    public static func tokens(_ command: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var quote: Character?
        var escaped = false

        func flush() {
            if !current.isEmpty {
                tokens.append(current)
                current = ""
            }
        }

        let characters = Array(command)
        var index = 0
        while index < characters.count {
            let character = characters[index]
            if escaped {
                current.append(character)
                escaped = false
                index += 1
                continue
            }
            if character == "\\", quote != "'" {
                escaped = true
                index += 1
                continue
            }
            if let activeQuote = quote {
                if character == activeQuote {
                    quote = nil
                } else {
                    current.append(character)
                }
                index += 1
                continue
            }
            if character == "'" || character == "\"" {
                quote = character
                index += 1
                continue
            }
            if character.isWhitespace {
                flush()
                if character == "\n" { tokens.append("\n") }
                index += 1
                continue
            }
            if character == ";" || character == "|" || character == "&" {
                flush()
                if index + 1 < characters.count, characters[index + 1] == character {
                    tokens.append(String([character, character]))
                    index += 2
                } else {
                    tokens.append(String(character))
                    index += 1
                }
                continue
            }
            current.append(character)
            index += 1
        }
        flush()
        return tokens
    }
}

private extension Array where Element == String {
    subscript(safe index: Int) -> String? {
        indices.contains(index) ? self[index] : nil
    }
}
