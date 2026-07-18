import XCTest
@testable import OffsendRuntime

final class OffsendMCPInventoryTests: XCTestCase {
    func testCollectsCursorProjectServersAndFlagsHighRisk() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("offsend-mcp-inv-\(UUID().uuidString)", isDirectory: true)
        let home = root.appendingPathComponent("home", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try FileManager.default.createDirectory(
            at: root.appendingPathComponent(".cursor"),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)

        let mcpJSON = """
        {
          "mcpServers": {
            "github": { "command": "npx", "args": ["-y", "@modelcontextprotocol/server-github"] },
            "filesystem": { "command": "npx", "args": ["-y", "@modelcontextprotocol/server-filesystem", "/tmp"] }
          }
        }
        """
        try mcpJSON.write(
            to: root.appendingPathComponent(".cursor/mcp.json"),
            atomically: true,
            encoding: .utf8
        )

        let report = OffsendMCPInventory().collect(projectRoot: root, homeDirectory: home)
        XCTAssertEqual(report.servers.count, 2)
        XCTAssertTrue(report.servers.contains { $0.name == "filesystem" && $0.highRisk })
        XCTAssertTrue(report.servers.contains { $0.name == "github" && !$0.highRisk })
        XCTAssertEqual(report.servers.first?.source, "cursor-project")
    }

    func testCustomHighRiskPatternsFromConfig() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("offsend-mcp-risk-\(UUID().uuidString)", isDirectory: true)
        let home = root.appendingPathComponent("home", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent(".cursor"),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try """
        {"mcpServers":{"acme-internal":{"url":"https://example.com/mcp"}}}
        """.write(to: root.appendingPathComponent(".cursor/mcp.json"), atomically: true, encoding: .utf8)

        let config = OffsendProjectMCPConfig(highRisk: ["acme-*"])
        let report = OffsendMCPInventory().collect(
            projectRoot: root,
            homeDirectory: home,
            mcpConfig: config
        )
        XCTAssertEqual(report.servers.count, 1)
        XCTAssertTrue(report.servers[0].highRisk)
    }

    func testDetailMasksSecretLikeArgsAndURLUserinfo() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("offsend-mcp-mask-\(UUID().uuidString)", isDirectory: true)
        let home = root.appendingPathComponent("home", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent(".cursor"),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)

        let mcpJSON = """
        {
          "mcpServers": {
            "acme": { "command": "npx", "args": ["acme-mcp", "--api-key", "sk-secret-value", "--token=tok-value", "--verbose"] },
            "magic": { "command": "npx", "args": ["-y", "@21st-dev/magic@latest", "API_KEY=\\"035bbd-secret\\""] },
            "remote": { "url": "https://user:hunter2@mcp.example.com/path" }
          }
        }
        """
        try mcpJSON.write(
            to: root.appendingPathComponent(".cursor/mcp.json"),
            atomically: true,
            encoding: .utf8
        )

        let report = OffsendMCPInventory().collect(projectRoot: root, homeDirectory: home)
        let acme = try XCTUnwrap(report.servers.first { $0.name == "acme" })
        XCTAssertFalse(acme.detail.contains("sk-secret-value"))
        XCTAssertFalse(acme.detail.contains("tok-value"))
        XCTAssertTrue(acme.detail.contains("--api-key ***"))
        XCTAssertTrue(acme.detail.contains("--token=***"))
        XCTAssertTrue(acme.detail.contains("--verbose"))

        let magic = try XCTUnwrap(report.servers.first { $0.name == "magic" })
        XCTAssertFalse(magic.detail.contains("035bbd-secret"))
        XCTAssertTrue(magic.detail.contains("API_KEY=***"))

        let remote = try XCTUnwrap(report.servers.first { $0.name == "remote" })
        XCTAssertFalse(remote.detail.contains("hunter2"))
        XCTAssertTrue(remote.detail.contains("https://***@mcp.example.com"))
    }

    func testLoadsContextMCPFromProjectConfig() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("offsend-mcp-cfg-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent(".git"), withIntermediateDirectories: true)

        let yaml = """
        version: 1
        context:
          mcp:
            mode: deny
            allow:
              - github
            deny:
              - "*"
            high_risk:
              - filesystem
        """
        try yaml.write(to: root.appendingPathComponent(".offsend.yml"), atomically: true, encoding: .utf8)

        let config = try XCTUnwrap(ProjectConfigLoader().load(from: root))
        XCTAssertEqual(config.context?.mcp?.mode, "deny")
        XCTAssertEqual(config.context?.mcp?.allow, ["github"])
        XCTAssertEqual(config.context?.mcp?.deny, ["*"])
        XCTAssertTrue(ProjectConfigValidator.validate(config).isEmpty)
    }
}
