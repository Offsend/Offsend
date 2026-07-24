import MaskingCore
import XCTest
@testable import OffsendRuntime

final class OffsendMCPJSONFieldTransformerTests: XCTestCase {
    private var keyData: Data!
    private var engine: SealEngine!

    override func setUpWithError() throws {
        keyData = Data((0..<32).map { _ in UInt8.random(in: 0...255) })
        engine = try SealEngine(keyData: keyData)
    }

    func testSealsBareKeyAtAnyDepthAndPassesSibling() throws {
        let input = """
        {"account_id":"12345","subscription":"pro","passport_number":"AB1234567","nested":{"passport_number":"CD999"}}
        """
        let result = try OffsendMCPJSONFieldTransformer.apply(
            jsonText: input,
            fields: [
                "passport_number": .seal,
                "account_id": .pass,
            ],
            sealPlaintext: { try self.engine.seal(plaintext: $0, type: "FIELD") }
        )
        XCTAssertEqual(result.sealedCount, 2)
        XCTAssertFalse(result.text.contains("AB1234567"))
        XCTAssertFalse(result.text.contains("CD999"))
        XCTAssertTrue(result.text.contains("12345"))
        XCTAssertTrue(result.text.contains("pro"))
        XCTAssertTrue(SealTokenDetector.containsSealTokens(in: result.text))
    }

    func testDropKeepsKeyAsNull() throws {
        let input = #"{"meta":{"filters":["a","b"]},"data":{"id":1}}"#
        let result = try OffsendMCPJSONFieldTransformer.apply(
            jsonText: input,
            fields: ["meta.filters": .drop],
            sealPlaintext: nil
        )
        XCTAssertEqual(result.droppedCount, 1)
        XCTAssertTrue(result.text.contains("\"filters\":null") || result.text.contains("\"filters\" : null"))
        XCTAssertTrue(result.text.contains("\"id\":1") || result.text.contains("\"id\": 1"))
    }

    func testDottedGlobAndArrayIndex() throws {
        let input = #"{"rows":[{"ssn":"111","ok":"x"},{"ssn":"222","ok":"y"}]}"#
        let result = try OffsendMCPJSONFieldTransformer.apply(
            jsonText: input,
            fields: ["rows.*.ssn": .seal],
            sealPlaintext: { try self.engine.seal(plaintext: $0, type: "FIELD") }
        )
        XCTAssertEqual(result.sealedCount, 2)
        XCTAssertFalse(result.text.contains("111"))
        XCTAssertTrue(result.text.contains("\"ok\":\"x\"") || result.text.contains("\"ok\" : \"x\""))
    }

    func testPassOverridesInheritedSeal() throws {
        let input = #"{"user":{"passport_number":"AB1","account_id":"99"}}"#
        let result = try OffsendMCPJSONFieldTransformer.apply(
            jsonText: input,
            fields: [
                "user": .seal,
                "user.account_id": .pass,
            ],
            sealPlaintext: { try self.engine.seal(plaintext: $0, type: "FIELD") }
        )
        XCTAssertEqual(result.sealedCount, 1)
        XCTAssertFalse(result.text.contains("AB1"))
        XCTAssertTrue(result.text.contains("99"))
    }

    func testSealRequiredWhenSealActionWithoutCallback() {
        XCTAssertThrowsError(
            try OffsendMCPJSONFieldTransformer.apply(
                jsonText: #"{"passport_number":"AB1"}"#,
                fields: ["passport_number": .seal],
                sealPlaintext: nil
            )
        ) { error in
            XCTAssertEqual(error as? OffsendMCPJSONFieldTransformError, .sealRequired)
        }
    }

    func testMoreSpecificPathWins() throws {
        let input = #"{"a":{"secret":"top"},"b":{"secret":"nested"}}"#
        let result = try OffsendMCPJSONFieldTransformer.apply(
            jsonText: input,
            fields: [
                "**.secret": .seal,
                "a.secret": .pass,
            ],
            sealPlaintext: { try self.engine.seal(plaintext: $0, type: "FIELD") }
        )
        XCTAssertTrue(result.text.contains("top"))
        XCTAssertFalse(result.text.contains("nested"))
        XCTAssertEqual(result.sealedCount, 1)
    }

    func testDecisionReportsFieldOnlyTransform() {
        let call = PromptMCPResponseCall(
            server: "crm",
            tool: "get_customer",
            responseText: "{}",
            canReplaceOutput: true,
            responseShape: .object
        )
        let decision = PromptMCPResponseGate.evaluate(
            call: call,
            mcpConfig: OffsendProjectMCPConfig(responses: "seal"),
            sealedOutput: #"{"passport_number":"{{FIELD:v1.x}}"}"#,
            sealedCount: 1,
            fieldsTransformed: 1
        )
        XCTAssertTrue(decision.hasFindings)
        XCTAssertTrue(decision.reason.contains("field policy"))
        XCTAssertEqual(decision.fieldsTransformed, 1)
    }
}
