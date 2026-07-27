import Foundation

public enum PrivilegedDaemonRisk: String, Equatable, Sendable {
    case confirm
    case deny
}

public struct PrivilegedDaemonInvocationMatch: Equatable, Sendable {
    public let surface: String
    public let operation: String
    public let risk: PrivilegedDaemonRisk

    public init(surface: String, operation: String, risk: PrivilegedDaemonRisk) {
        self.surface = surface
        self.operation = operation
        self.risk = risk
    }
}

/// Detects static access to privileged container daemons. Launching or
/// attaching to containers is denied because the daemon executes outside the
/// agent sandbox. Lower-risk daemon mutations require explicit confirmation.
public enum PrivilegedDaemonInvocationClassifier {
    private static let directSocketClients = ["curl", "socat", "nc", "ncat"]
    private static let containerCLIs = ["docker", "podman", "nerdctl"]
    private static let composeCLIs = ["docker-compose", "podman-compose"]
    private static let vmManagers: Set<String> = ["colima", "limactl", "lima", "orb", "orbctl"]

    public static func classify(command: String) -> PrivilegedDaemonInvocationMatch? {
        let tokens = ShellInvocationExtractor.allTokens(in: command)
        if let socket = directlyAccessedSocket(tokens: tokens, command: command) {
            return PrivilegedDaemonInvocationMatch(
                surface: socket,
                operation: "direct socket access",
                risk: .deny
            )
        }

        for invocation in ShellInvocationExtractor.invocations(in: command).map(\.arguments) {
            guard let executable = invocation.first.map(executableName) else { continue }
            if let match = classifyVirtualMachineManager(
                executable: executable,
                arguments: Array(invocation.dropFirst())
            ) {
                return match
            }
            if containerCLIs.contains(executable),
               let match = classifyContainerCLI(executable: executable, arguments: Array(invocation.dropFirst())) {
                return match
            }
            if composeCLIs.contains(executable),
               let operation = firstPositional(Array(invocation.dropFirst())) {
                if ["up", "run", "create", "start", "restart", "exec", "cp"].contains(operation) {
                    return denied(executable, operation: operation)
                }
                if !["config", "version", "ps", "images", "logs", "top", "ls"].contains(operation) {
                    return confirmation(executable, operation: operation)
                }
            }
            if executable == "ctr",
               let match = classifyCTR(arguments: Array(invocation.dropFirst())) {
                return match
            }
            if executable == "buildctl",
               invocation.dropFirst().contains("build") {
                return PrivilegedDaemonInvocationMatch(
                    surface: "BuildKit daemon",
                    operation: "build",
                    risk: hasUnsafeBuildEntitlement(invocation) ? .deny : .confirm
                )
            }
        }
        return nil
    }

    private static func classifyContainerCLI(
        executable: String,
        arguments: [String]
    ) -> PrivilegedDaemonInvocationMatch? {
        if hasExplicitDaemonEndpoint(arguments) {
            return PrivilegedDaemonInvocationMatch(
                surface: "\(executable) daemon",
                operation: "explicit endpoint selection",
                risk: .deny
            )
        }
        let args = dropGlobalOptions(arguments)
        guard let command = args.first else { return nil }
        let remainder = Array(args.dropFirst())

        if hasElevatedContainerOption(args) {
            return PrivilegedDaemonInvocationMatch(
                surface: "\(executable) daemon",
                operation: "elevated \(command)",
                risk: .deny
            )
        }
        if ["run", "create", "exec", "start", "attach", "cp"].contains(command) {
            return denied(executable, operation: command)
        }
        if command == "container", let operation = firstPositional(remainder) {
            if ["run", "create", "exec", "start", "attach", "cp"].contains(operation) {
                return denied(executable, operation: "container \(operation)")
            }
            return confirmation(executable, operation: "container \(operation)")
        }
        if command == "compose", let operation = firstPositional(remainder) {
            if ["up", "run", "create", "start", "restart", "exec", "cp"].contains(operation) {
                return denied(executable, operation: "compose \(operation)")
            }
            if ["config", "version", "ps", "images", "logs", "top", "ls"].contains(operation) {
                return nil
            }
            return confirmation(executable, operation: "compose \(operation)")
        }
        if command == "plugin", let operation = firstPositional(remainder) {
            if ["install", "enable", "upgrade", "set"].contains(operation) {
                return denied(executable, operation: "plugin \(operation)")
            }
            return operation == "ls" || operation == "inspect"
                ? nil
                : confirmation(executable, operation: "plugin \(operation)")
        }
        if command == "build" || (command == "buildx" && firstPositional(remainder) == "build") {
            return PrivilegedDaemonInvocationMatch(
                surface: "\(executable) daemon",
                operation: command == "build" ? "build" : "buildx build",
                risk: hasUnsafeBuildEntitlement(args) ? .deny : .confirm
            )
        }
        if ["image", "context", "volume", "network"].contains(command),
           let operation = firstPositional(remainder) {
            if ["ls", "list", "inspect", "show", "history"].contains(operation) {
                return nil
            }
            return confirmation(executable, operation: "\(command) \(operation)")
        }
        if safeContainerCommands.contains(command) {
            return nil
        }
        return confirmation(executable, operation: command)
    }

    /// The VM managers behind Docker on macOS mount the host home directory, so
    /// getting a shell inside one is a way out of the agent sandbox.
    private static func classifyVirtualMachineManager(
        executable: String,
        arguments: [String]
    ) -> PrivilegedDaemonInvocationMatch? {
        guard vmManagers.contains(executable) else { return nil }
        guard let operation = firstPositional(dropGlobalOptions(arguments)) else { return nil }
        if ["ssh", "shell", "run", "exec", "nerdctl", "docker", "kubectl"].contains(operation) {
            return denied(executable, operation: operation)
        }
        if ["list", "ls", "status", "version", "info"].contains(operation) { return nil }
        return confirmation(executable, operation: operation)
    }

    private static func classifyCTR(arguments: [String]) -> PrivilegedDaemonInvocationMatch? {
        let args = dropGlobalOptions(arguments)
        guard let command = args.first else { return nil }
        let operation = firstPositional(Array(args.dropFirst()))
        if command == "run"
            || (command == "tasks" && ["start", "exec", "attach"].contains(operation ?? "")) {
            return denied("containerd", operation: [command, operation].compactMap { $0 }.joined(separator: " "))
        }
        if ["version", "plugins", "namespaces", "images", "containers"].contains(command) {
            return nil
        }
        return confirmation("containerd", operation: command)
    }

    private static func directlyAccessedSocket(tokens: [String], command: String) -> String? {
        if let endpoint = tokens.compactMap(daemonEndpoint).first {
            return endpoint
        }
        guard let socket = knownSocketMarker(in: command) else { return nil }
        if tokens.contains(where: { token in
            let name = executableName(token)
            return directSocketClients.contains(name)
        }) {
            return socket
        }
        return nil
    }

    private static func daemonEndpoint(_ token: String) -> String? {
        for name in ["DOCKER_HOST=", "DOCKER_CONTEXT=", "CONTAINER_HOST=", "BUILDKIT_HOST="]
            where token.hasPrefix(name) {
            let value = String(token.dropFirst(name.count))
            return value.isEmpty ? String(name.dropLast()) : value
        }
        return nil
    }

    private static func hasExplicitDaemonEndpoint(_ arguments: [String]) -> Bool {
        for (index, token) in arguments.enumerated() {
            if token.hasPrefix("--host=")
                || (token.hasPrefix("-H") && token.count > 2)
                || token.hasPrefix("--context=") {
                return true
            }
            if ["--host", "-H", "--context"].contains(token), index + 1 < arguments.count {
                return true
            }
        }
        return false
    }

    static func knownSocketMarker(in text: String) -> String? {
        let lower = text.lowercased()
        let markers = [
            "docker.sock",
            "podman.sock",
            "containerd.sock",
            "buildkitd.sock",
            "unix://",
        ]
        return markers.first(where: lower.contains)
    }

    private static func hasElevatedContainerOption(_ arguments: [String]) -> Bool {
        let joined = arguments.joined(separator: " ").lowercased()
        let deniedMarkers = [
            "--privileged",
            "--device",
            "--device-cgroup-rule",
            "--pid=host",
            "--network=host",
            "--net=host",
            "--ipc=host",
            "--uts=host",
            "--userns=host",
            "--cgroupns=host",
            "--security-opt=seccomp=unconfined",
            "--security-opt=apparmor=unconfined",
            "--cap-add=all",
            "--cap-add=sys_admin",
            "--cap-add sys_admin",
        ]
        return deniedMarkers.contains(where: joined.contains)
            || knownSocketMarker(in: joined) != nil
    }

    private static func hasUnsafeBuildEntitlement<S: Sequence>(_ arguments: S) -> Bool
    where S.Element == String {
        let joined = arguments.joined(separator: " ").lowercased()
        return joined.contains("security.insecure")
            || joined.contains("network.host")
            || knownSocketMarker(in: joined) != nil
    }

    private static func dropGlobalOptions(_ arguments: [String]) -> [String] {
        let optionsWithValue = [
            "--config", "--context", "--host", "-H", "--log-level",
            "--namespace", "-n", "--address", "-a", "--timeout",
        ]
        var index = 0
        while index < arguments.count {
            let token = arguments[index]
            if optionsWithValue.contains(token) {
                index += 2
                continue
            }
            if token.hasPrefix("-") {
                index += 1
                continue
            }
            break
        }
        return index < arguments.count ? Array(arguments[index...]) : []
    }

    private static func firstPositional(_ arguments: [String]) -> String? {
        arguments.first { !$0.hasPrefix("-") }
    }

    private static func denied(_ surface: String, operation: String) -> PrivilegedDaemonInvocationMatch {
        PrivilegedDaemonInvocationMatch(
            surface: surface == "containerd" ? surface : "\(surface) daemon",
            operation: operation,
            risk: .deny
        )
    }

    private static func confirmation(
        _ surface: String,
        operation: String
    ) -> PrivilegedDaemonInvocationMatch {
        PrivilegedDaemonInvocationMatch(
            surface: "\(surface) daemon",
            operation: operation,
            risk: .confirm
        )
    }

    private static func executableName(_ token: String) -> String {
        token.split(separator: "/").last.map(String.init) ?? token
    }

    private static let safeContainerCommands: Set<String> = [
        "version", "info", "ps", "images", "inspect", "logs", "top",
        "stats", "events", "port", "diff", "history",
    ]
}
