import XCTest
@testable import OffsendRuntime

final class HookCoverageGapsTests: XCTestCase {
    func testCloudSessionsAlwaysPresentWhenAnyEditorInstalled() {
        let gaps = HookCoverageGap.active(
            cursorInstalled: false,
            claudeInstalled: false,
            mcpSurfaceActive: false
        )
        XCTAssertEqual(gaps, [.cloudSessions])
    }

    func testActiveGapsMatchInstalledSurface() {
        let gaps = HookCoverageGap.active(
            cursorInstalled: true,
            claudeInstalled: true,
            mcpSurfaceActive: true
        )
        XCTAssertEqual(
            gaps,
            [.mcpResponses, .claudeSubagents, .cursorOpenTabs, .cloudSessions]
        )
    }

    func testActiveMCPResponseProtectionClosesResponseGap() {
        let covered = HookCoverageGap.active(
            cursorInstalled: false,
            claudeInstalled: true,
            mcpSurfaceActive: true,
            mcpResponseProtectedClaude: true
        )
        XCTAssertFalse(covered.contains(.mcpResponses))

        let uncovered = HookCoverageGap.active(
            cursorInstalled: false,
            claudeInstalled: true,
            mcpSurfaceActive: true,
            mcpResponseProtectedClaude: false
        )
        XCTAssertTrue(uncovered.contains(.mcpResponses))
    }

    func testAllInstalledTargetsMustActivelyProtectResponses() {
        let cursorUnprotected = HookCoverageGap.active(
            cursorInstalled: true,
            claudeInstalled: true,
            mcpSurfaceActive: true,
            mcpResponseProtectedCursor: false,
            mcpResponseProtectedClaude: true
        )
        XCTAssertTrue(cursorUnprotected.contains(.mcpResponses))

        let bothProtected = HookCoverageGap.active(
            cursorInstalled: true,
            claudeInstalled: true,
            mcpSurfaceActive: true,
            mcpResponseProtectedCursor: true,
            mcpResponseProtectedClaude: true
        )
        XCTAssertFalse(bothProtected.contains(.mcpResponses))
    }

    func testMCPResponseProtectionRequiresCompleteRuntimeConditions() {
        XCTAssertTrue(MCPResponseProtection.isActive(
            hookInstalled: true,
            replacementEventInstalled: true,
            wrapperHealthy: true,
            configuredMode: "seal",
            sealKeyAvailable: true
        ))
        XCTAssertFalse(MCPResponseProtection.isActive(
            hookInstalled: true,
            replacementEventInstalled: true,
            wrapperHealthy: true,
            configuredMode: "warn",
            sealKeyAvailable: true
        ))
        XCTAssertFalse(MCPResponseProtection.isActive(
            hookInstalled: true,
            replacementEventInstalled: true,
            wrapperHealthy: true,
            configuredMode: "seal",
            sealKeyAvailable: false
        ))
        XCTAssertFalse(MCPResponseProtection.isActive(
            hookInstalled: true,
            replacementEventInstalled: false,
            wrapperHealthy: true,
            configuredMode: "seal",
            sealKeyAvailable: true
        ))
    }

    func testDoctorMessageListsGapsWithoutSandboxClaim() {
        let message = HookCoverageGap.doctorMessage(for: [.mcpResponses, .cloudSessions])
        XCTAssertTrue(message.contains("MCP response payloads"))
        XCTAssertTrue(message.contains("cloud agent sessions"))
        XCTAssertTrue(message.contains("not a sandbox"))
        XCTAssertTrue(message.contains("what-hooks-do-not-cover"))
        XCTAssertFalse(message.localizedCaseInsensitiveContains("prevent escape"))
    }

    func testCloudSessionsAloneAreNotActionableWarn() {
        XCTAssertFalse(HookCoverageGap.hasActionableGaps([.cloudSessions]))
        XCTAssertTrue(HookCoverageGap.hasActionableGaps([.mcpResponses, .cloudSessions]))
        XCTAssertTrue(HookCoverageGap.hasActionableGaps([.claudeSubagents]))
    }

    func testKnownGapsAreDocumentedInCLIBypassTable() throws {
        // Lock product docs: every HookCoverageGap must appear in the bypass table.
        // Tests/ → OffsendRuntime/ → Core/ → repo root
        let cliURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("docs/cli.md")
        let cli = try String(contentsOf: cliURL, encoding: .utf8)
        XCTAssertTrue(cli.contains("### What hooks do not cover"), "missing section in \(cliURL.path)")
        XCTAssertTrue(cli.contains("MCP tool responses"))
        XCTAssertTrue(cli.contains("Subagents (Claude"))
        XCTAssertTrue(cli.contains("Open editor tabs (Cursor)"))
        XCTAssertTrue(cli.contains("Cloud agent sessions"))
        XCTAssertTrue(cli.contains("Renamed copies"))
    }
}
