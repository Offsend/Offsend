import XCTest
@testable import OffsendRuntime

final class OffsendPolicyTrustFilterTests: XCTestCase {
    func testDropsFieldsThatNarrowGateCoverage() {
        let hardened = OffsendPolicyTrustFilter.hardened(
            OffsendProjectConfig(
                check: OffsendProjectCheckConfig(
                    failOn: "high",
                    exclude: ["**/*"],
                    detectors: OffsendProjectDetectorsConfig(disable: ["aws-access-key"]),
                    dictionaries: [OffsendProjectDictionaryEntry(kind: "literal", value: "acme")]
                )
            )
        )

        XCTAssertNil(hardened?.check?.exclude)
        XCTAssertNil(hardened?.check?.detectors)
        // Dictionaries only add findings, so they survive.
        XCTAssertEqual(hardened?.check?.dictionaries?.count, 1)
        XCTAssertEqual(hardened?.check?.failOn, "high")
    }

    func testKeepsEnforcementModesOnlyWhenAtLeastAsStrictAsDefault() {
        let loosened = OffsendPolicyTrustFilter.hardened(
            OffsendProjectConfig(
                context: OffsendProjectContextConfig(
                    mcp: OffsendProjectMCPConfig(
                        mode: "observe",
                        rules: [OffsendMCPRule(match: .init(server: "*"), mode: "observe")]
                    ),
                    subagents: OffsendProjectSubagentsConfig(mode: "ask", scanTask: false),
                    read: OffsendProjectReadConfig(onSecret: "seal")
                )
            )
        )

        XCTAssertNil(loosened?.context?.mcp?.mode)
        XCTAssertNil(loosened?.context?.mcp?.rules?.first?.mode)
        XCTAssertNil(loosened?.context?.subagents?.mode)
        XCTAssertNil(loosened?.context?.subagents?.scanTask)
        // Seal still denies the read and withholds detected secrets, so it
        // survives an untrusted policy.
        XCTAssertEqual(loosened?.context?.read?.onSecret, "seal")

        let tightened = OffsendPolicyTrustFilter.hardened(
            OffsendProjectConfig(
                context: OffsendProjectContextConfig(
                    mcp: OffsendProjectMCPConfig(mode: "deny", deny: ["*"], responses: "seal"),
                    subagents: OffsendProjectSubagentsConfig(mode: "deny", scanTask: true)
                )
            )
        )

        XCTAssertEqual(tightened?.context?.mcp?.mode, "deny")
        XCTAssertEqual(tightened?.context?.mcp?.deny, ["*"])
        XCTAssertEqual(tightened?.context?.mcp?.responses, "seal")
        XCTAssertEqual(tightened?.context?.subagents?.mode, "deny")
    }

    func testHardenedDefaultsMatchAbsentPolicy() {
        let hardened = OffsendPolicyTrustFilter.hardened(
            OffsendProjectConfig(
                context: OffsendProjectContextConfig(
                    mcp: OffsendProjectMCPConfig(mode: "observe"),
                    subagents: OffsendProjectSubagentsConfig(mode: "observe")
                )
            )
        )

        XCTAssertEqual(
            OffsendMCPRuleResolver.effectiveMode(
                mcpConfig: hardened?.context?.mcp,
                server: "any",
                tool: "any"
            ),
            .ask
        )
        XCTAssertEqual(
            OffsendContextEnforcementMode(rawValue: hardened?.context?.subagents?.mode ?? ""),
            nil
        )
    }
}
