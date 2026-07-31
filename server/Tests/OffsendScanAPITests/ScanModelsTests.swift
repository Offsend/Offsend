import XCTest
@testable import OffsendScanAPI

final class ScanModelsTests: XCTestCase {
    func testScanJobRecordReportURLWhenHTMLStored() {
        let record = ScanJobRecord(
            id: "abc",
            repoURL: "https://github.com/org/repo",
            status: .completed,
            createdAt: Date(),
            updatedAt: Date(),
            reportJSON: nil,
            reportHTMLKey: "reports/abc.html",
            errorMessage: nil
        )
        XCTAssertEqual(record.reportURL, "/r/abc")
    }

    func testScanJobRecordReportURLNilWithoutHTMLKey() {
        let record = ScanJobRecord(
            id: "abc",
            repoURL: "https://github.com/org/repo",
            status: .queued,
            createdAt: Date(),
            updatedAt: Date(),
            reportJSON: nil,
            reportHTMLKey: nil,
            errorMessage: nil
        )
        XCTAssertNil(record.reportURL)
    }

    func testScanJobStatusCodableRoundTrip() throws {
        for status in [ScanJobStatus.queued, .running, .completed, .failed] {
            let data = try JSONEncoder().encode(status)
            let decoded = try JSONDecoder().decode(ScanJobStatus.self, from: data)
            XCTAssertEqual(decoded, status)
        }
    }

    func testCreateScanResponseEncodesExpectedFields() throws {
        let response = CreateScanResponse(
            jobID: "job-1",
            statusURL: "/scan/job-1",
            reportURL: "/r/job-1",
            pollIntervalMs: 2000
        )
        let data = try JSONEncoder().encode(response)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(json["jobID"] as? String, "job-1")
        XCTAssertEqual(json["statusURL"] as? String, "/scan/job-1")
        XCTAssertEqual(json["reportURL"] as? String, "/r/job-1")
        XCTAssertEqual(json["pollIntervalMs"] as? Int, 2000)
    }

    func testReportPayloadDecodeFromValidJSON() {
        let json = TestSupport.sampleReportJSON()
        let payload = ScanStatusResponse.ReportPayload.decode(from: json)
        XCTAssertNotNil(payload)
        XCTAssertEqual(payload?.schemaVersion, 1)
        XCTAssertEqual(payload?.scanComplete, true)
        XCTAssertEqual(payload?.ignoreFilesPresent["cursor-ignore"], true)
        XCTAssertEqual(payload?.errors, [])
    }

    func testReportPayloadDecodeReturnsNilForInvalidJSON() {
        XCTAssertNil(ScanStatusResponse.ReportPayload.decode(from: "not-json"))
    }

    func testJSONValueRoundTrip() throws {
        let values: [JSONValue] = [
            .string("hello"),
            .int(42),
            .bool(true),
            .null,
            .array([.int(1), .string("two")]),
            .object(["nested": .bool(false), "count": .int(3)]),
        ]

        for value in values {
            let data = try JSONEncoder().encode(value)
            let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
            XCTAssertEqual(decoded, value)
        }
    }

    func testJSONValueDecodesMixedObject() throws {
        let json = """
        { "name": "test", "count": 1, "ok": true, "empty": null, "items": [1, 2] }
        """
        let decoded = try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
        guard case let .object(fields) = decoded else {
            return XCTFail("Expected object")
        }
        XCTAssertEqual(fields["name"], .string("test"))
        XCTAssertEqual(fields["count"], .int(1))
        XCTAssertEqual(fields["ok"], .bool(true))
        XCTAssertEqual(fields["empty"], .null)
        XCTAssertEqual(fields["items"], .array([.int(1), .int(2)]))
    }
}
