import XCTest
@testable import OffsendRuntime

final class OffsendMCPRuleTests: XCTestCase {
    func testExactToolBeatsWildcard() {
        let config = OffsendProjectMCPConfig(
            responses: "seal",
            rules: [
                OffsendMCPRule(
                    match: OffsendMCPRuleMatch(server: "github", tool: "*"),
                    responses: "warn"
                ),
                OffsendMCPRule(
                    match: OffsendMCPRuleMatch(server: "github", tool: "list_issues"),
                    responses: "observe"
                ),
            ]
        )
        XCTAssertEqual(
            OffsendMCPRuleResolver.effectiveResponseMode(
                mcpConfig: config,
                server: "github",
                tool: "list_issues"
            ),
            .observe
        )
        XCTAssertEqual(
            OffsendMCPRuleResolver.effectiveResponseMode(
                mcpConfig: config,
                server: "github",
                tool: "get_file"
            ),
            .warn
        )
    }

    func testServerSpecificBeatsToolOnlyWildcardServer() {
        let config = OffsendProjectMCPConfig(
            mode: "ask",
            rules: [
                OffsendMCPRule(
                    match: OffsendMCPRuleMatch(tool: "query"),
                    mode: "observe"
                ),
                OffsendMCPRule(
                    match: OffsendMCPRuleMatch(server: "postgres", tool: "*"),
                    mode: "deny"
                ),
            ]
        )
        XCTAssertEqual(
            OffsendMCPRuleResolver.effectiveMode(
                mcpConfig: config,
                server: "postgres",
                tool: "query"
            ),
            .deny
        )
    }

    func testEarlierRuleWinsOnEqualSpecificity() {
        let config = OffsendProjectMCPConfig(
            responses: "seal",
            rules: [
                OffsendMCPRule(
                    match: OffsendMCPRuleMatch(server: "crm", tool: "get_*"),
                    responses: "observe"
                ),
                OffsendMCPRule(
                    match: OffsendMCPRuleMatch(server: "crm", tool: "get_*"),
                    responses: "warn"
                ),
            ]
        )
        XCTAssertEqual(
            OffsendMCPRuleResolver.effectiveResponseMode(
                mcpConfig: config,
                server: "crm",
                tool: "get_customer"
            ),
            .observe
        )
    }

    func testUnsetRuleFieldFallsBackToGlobal() {
        let config = OffsendProjectMCPConfig(
            mode: "deny",
            responses: "seal",
            rules: [
                OffsendMCPRule(
                    match: OffsendMCPRuleMatch(server: "github", tool: "list_issues"),
                    responses: "observe"
                ),
            ]
        )
        XCTAssertEqual(
            OffsendMCPRuleResolver.effectiveMode(
                mcpConfig: config,
                server: "github",
                tool: "list_issues"
            ),
            .deny
        )
        XCTAssertEqual(
            OffsendMCPRuleResolver.effectiveResponseMode(
                mcpConfig: config,
                server: "github",
                tool: "list_issues"
            ),
            .observe
        )
    }

    func testNoMatchUsesGlobalDefaults() {
        let config = OffsendProjectMCPConfig(
            mode: "observe",
            responses: "warn",
            rules: [
                OffsendMCPRule(
                    match: OffsendMCPRuleMatch(server: "postgres"),
                    mode: "deny",
                    responses: "seal"
                ),
            ]
        )
        XCTAssertEqual(
            OffsendMCPRuleResolver.effectiveMode(
                mcpConfig: config,
                server: "github",
                tool: "search"
            ),
            .observe
        )
        XCTAssertEqual(
            OffsendMCPRuleResolver.effectiveResponseMode(
                mcpConfig: config,
                server: "github",
                tool: "search"
            ),
            .warn
        )
    }

    func testCaseInsensitiveMatch() {
        let config = OffsendProjectMCPConfig(
            rules: [
                OffsendMCPRule(
                    match: OffsendMCPRuleMatch(server: "GitHub", tool: "List_Issues"),
                    responses: "observe"
                ),
            ]
        )
        XCTAssertEqual(
            OffsendMCPRuleResolver.effectiveResponseMode(
                mcpConfig: config,
                server: "github",
                tool: "list_issues"
            ),
            .observe
        )
    }

    func testFieldActionsMergeAcrossMatchingRules() {
        let config = OffsendProjectMCPConfig(
            responses: "seal",
            rules: [
                OffsendMCPRule(
                    match: OffsendMCPRuleMatch(server: "crm", tool: "*"),
                    fields: [
                        "passport_number": "seal",
                        "account_id": "pass",
                    ]
                ),
                // Narrower rule without fields must keep broader fields.
                OffsendMCPRule(
                    match: OffsendMCPRuleMatch(server: "crm", tool: "get_customer"),
                    responses: "seal"
                ),
            ]
        )
        let actions = OffsendMCPRuleResolver.effectiveFieldActions(
            mcpConfig: config,
            server: "crm",
            tool: "get_customer"
        )
        XCTAssertEqual(actions["passport_number"], .seal)
        XCTAssertEqual(actions["account_id"], .pass)
    }

    func testMoreSpecificFieldActionOverridesBroader() {
        let config = OffsendProjectMCPConfig(
            responses: "seal",
            rules: [
                OffsendMCPRule(
                    match: OffsendMCPRuleMatch(server: "crm"),
                    fields: ["ssn": "seal", "email": "seal"]
                ),
                OffsendMCPRule(
                    match: OffsendMCPRuleMatch(server: "crm", tool: "get_customer"),
                    fields: ["ssn": "pass"]
                ),
            ]
        )
        let actions = OffsendMCPRuleResolver.effectiveFieldActions(
            mcpConfig: config,
            server: "crm",
            tool: "get_customer"
        )
        XCTAssertEqual(actions["ssn"], .pass)
        XCTAssertEqual(actions["email"], .seal)
    }
}
