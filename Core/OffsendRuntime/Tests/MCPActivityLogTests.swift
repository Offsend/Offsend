import XCTest
@testable import OffsendRuntime

final class MCPActivityLogTests: XCTestCase {
    func testAppendAndSummarizeFindings() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("mcp-activity.log")

        MCPActivityLog.append(
            MCPActivityLog.Entry(
                kind: "mcp_response",
                server: "crm",
                tool: "get_customer",
                code: "mcp_response_sealed",
                secretTypes: ["apiKeyGeneric"],
                fieldsTransformed: 1
            ),
            to: url
        )
        MCPActivityLog.append(
            MCPActivityLog.Entry(
                kind: "mcp_response",
                server: "crm",
                tool: "get_customer",
                code: "mcp_response_sealed",
                fieldsTransformed: 2
            ),
            to: url
        )
        MCPActivityLog.append(
            MCPActivityLog.Entry(
                kind: "mcp_call",
                server: "github",
                tool: "list_issues",
                code: "allow"
            ),
            to: url
        )

        let findings = MCPActivityLog.recentFindingSummaries(from: url)
        XCTAssertEqual(findings.count, 1)
        XCTAssertEqual(findings[0].label, "crm/get_customer")
        XCTAssertEqual(findings[0].count, 2)
        XCTAssertEqual(findings[0].fieldsTransformed, 2)
    }

    func testUncoveredHighRiskAndActivityAdvice() {
        let servers = [
            ShowMCPServer(name: "postgres", source: "cursor", detail: "", highRisk: true),
            ShowMCPServer(name: "github", source: "cursor", detail: "", highRisk: false),
            ShowMCPServer(name: "filesystem", source: "cursor", detail: "", highRisk: true),
        ]
        let rules = [
            OffsendMCPRule(match: OffsendMCPRuleMatch(server: "github"), responses: "observe"),
            // Tool-only rules must not count as covering a high-risk server.
            OffsendMCPRule(match: OffsendMCPRuleMatch(tool: "query"), mode: "deny"),
        ]
        XCTAssertEqual(
            OffsendMCPRuleAdvice.uncoveredHighRiskServers(servers: servers, rules: rules),
            ["filesystem", "postgres"]
        )

        let hits = [
            MCPActivityLog.HitSummary(
                server: "crm",
                tool: "get_customer",
                kind: "mcp_response",
                count: 3,
                lastCode: "mcp_response_sealed",
                secretTypes: [],
                fieldsTransformed: 1
            ),
        ]
        XCTAssertEqual(
            OffsendMCPRuleAdvice.uncoveredActivityHits(hits: hits, rules: rules).first?.label,
            "crm/get_customer"
        )
        let covered = [
            OffsendMCPRule(match: OffsendMCPRuleMatch(server: "crm", tool: "get_customer"), fields: ["x": "seal"]),
        ]
        XCTAssertTrue(OffsendMCPRuleAdvice.uncoveredActivityHits(hits: hits, rules: covered).isEmpty)
    }

    func testFieldsWithoutSealResponsesAdvice() {
        XCTAssertTrue(
            OffsendMCPRuleAdvice.hasFieldsWithoutSealResponses(
                rules: [
                    OffsendMCPRule(
                        match: OffsendMCPRuleMatch(server: "crm"),
                        fields: ["ssn": "seal"]
                    ),
                    OffsendMCPRule(
                        match: OffsendMCPRuleMatch(server: "github"),
                        responses: "seal"
                    ),
                ],
                globalResponses: "observe"
            )
        )
        XCTAssertFalse(
            OffsendMCPRuleAdvice.hasFieldsWithoutSealResponses(
                rules: [
                    OffsendMCPRule(
                        match: OffsendMCPRuleMatch(server: "crm"),
                        fields: ["ssn": "seal"]
                    ),
                ],
                globalResponses: "seal"
            )
        )
        XCTAssertFalse(
            OffsendMCPRuleAdvice.hasFieldsWithoutSealResponses(
                rules: [
                    OffsendMCPRule(
                        match: OffsendMCPRuleMatch(server: "crm"),
                        responses: "seal",
                        fields: ["ssn": "seal"]
                    ),
                ],
                globalResponses: "observe"
            )
        )
    }

    func testShowReporterRendersRulesAndActivity() {
        let report = ShowReport(
            directoryPath: "/tmp/project",
            groups: [],
            totalExposedCount: 0,
            scanIncomplete: false,
            errors: [],
            mcp: ShowMCPSection(
                servers: [
                    ShowMCPServer(
                        name: "postgres",
                        source: "cursor-project",
                        detail: "",
                        highRisk: true
                    ),
                ],
                policyMode: "ask",
                responsesMode: "seal",
                gateTargets: ["cursor"],
                rules: [
                    ShowMCPRule(summary: "postgres/* → mode: ask; responses: seal"),
                ],
                recentActivity: [
                    ShowMCPActivityHit(
                        server: "crm",
                        tool: "get_customer",
                        kind: "mcp_response",
                        count: 2,
                        lastCode: "mcp_response_sealed",
                        fieldsTransformed: 1
                    ),
                ],
                hints: ["high-risk without rules: filesystem"]
            )
        )
        let output = ShowReporter().render(report, format: .text)
        XCTAssertTrue(output.contains("rules: 1"))
        XCTAssertTrue(output.contains("postgres/* → mode: ask"))
        XCTAssertTrue(output.contains("recent MCP findings"))
        XCTAssertTrue(output.contains("crm/get_customer"))
        XCTAssertTrue(output.contains("high-risk without rules"))

        let json = ShowReporter().render(report, format: .json)
        XCTAssertTrue(json.contains("\"responsesMode\""))
        XCTAssertTrue(json.contains("\"recentActivity\""))
        XCTAssertTrue(json.contains("get_customer"))
    }
}
