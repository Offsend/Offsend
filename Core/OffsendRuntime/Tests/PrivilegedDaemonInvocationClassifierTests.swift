import XCTest
@testable import OffsendRuntime

final class PrivilegedDaemonInvocationClassifierTests: XCTestCase {
    func testDeniesContainerExecutionAndAttachment() {
        let commands = [
            "docker run --rm alpine id",
            "docker container exec app sh",
            "docker start stopped-container",
            "docker compose up -d",
            "docker-compose up -d",
            "podman create alpine",
            "nerdctl exec app sh",
            "sudo -u root docker run alpine id",
            "ctr run image ref",
            "ctr tasks exec --exec-id shell container sh",
        ]

        for command in commands {
            XCTAssertEqual(
                PrivilegedDaemonInvocationClassifier.classify(command: command)?.risk,
                .deny,
                command
            )
        }
    }

    func testDeniesElevatedFlagsAndPlugins() {
        let commands = [
            "docker build --allow security.insecure .",
            "docker buildx build --allow=network.host .",
            "docker plugin install example/plugin",
            "podman run --privileged alpine",
            "docker run --cap-add=SYS_ADMIN alpine",
            "docker run -v /var/run/docker.sock:/var/run/docker.sock alpine",
        ]

        for command in commands {
            XCTAssertEqual(
                PrivilegedDaemonInvocationClassifier.classify(command: command)?.risk,
                .deny,
                command
            )
        }
    }

    func testDeniesDirectSocketAndRemoteEndpointAccess() {
        let commands = [
            "curl --unix-socket /var/run/docker.sock http://localhost/version",
            "socat - UNIX-CONNECT:/run/containerd/containerd.sock",
            "DOCKER_HOST=tcp://daemon.internal:2375 docker ps",
            "BUILDKIT_HOST=unix:///run/buildkit/buildkitd.sock buildctl debug workers",
            "DOCKER_CONTEXT=production docker ps",
            "docker --host=tcp://daemon.internal:2375 ps",
        ]

        for command in commands {
            let match = PrivilegedDaemonInvocationClassifier.classify(command: command)
            XCTAssertEqual(match?.risk, .deny, command)
        }
    }

    func testConfirmsLowerRiskDaemonMutations() {
        let commands = [
            "docker build .",
            "docker pull alpine",
            "docker image rm alpine",
            "docker context use remote",
            "podman volume create cache",
            "buildctl build --frontend dockerfile.v0",
        ]

        for command in commands {
            XCTAssertEqual(
                PrivilegedDaemonInvocationClassifier.classify(command: command)?.risk,
                .confirm,
                command
            )
        }
    }

    func testDeniesShellAccessToDockerBackingVirtualMachines() {
        for command in ["colima ssh", "limactl shell default", "orb run bash", "colima nerdctl run alpine"] {
            let match = PrivilegedDaemonInvocationClassifier.classify(command: command)
            XCTAssertEqual(match?.risk, .deny, command)
        }
        XCTAssertNil(PrivilegedDaemonInvocationClassifier.classify(command: "colima status"))
        XCTAssertEqual(
            PrivilegedDaemonInvocationClassifier.classify(command: "colima start")?.risk,
            .confirm
        )
    }

    func testFindsDaemonInvocationThroughShellWrappers() {
        for command in [
            #"bash -c "docker run --privileged alpine""#,
            "timeout 30 docker exec app sh",
        ] {
            XCTAssertEqual(
                PrivilegedDaemonInvocationClassifier.classify(command: command)?.risk,
                .deny,
                command
            )
        }
    }

    func testAllowsDiagnosticsAndUnrelatedText() {
        let commands = [
            "docker version",
            "docker ps",
            "docker images",
            "docker inspect app",
            "docker image inspect alpine",
            "docker context ls",
            "ctr images list",
            "echo docker run alpine",
            #"printf '%s' "curl --unix-socket /var/run/docker.sock""#,
        ]

        for command in commands {
            XCTAssertNil(
                PrivilegedDaemonInvocationClassifier.classify(command: command),
                command
            )
        }
    }
}
