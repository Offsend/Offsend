import XCTest
@testable import DetectionCore

final class BIOSpanDecoderTests: XCTestCase {
    func testDecodesSimpleBIOSequence() {
        let text = "John Smith lives here"
        let johnRange = text.range(of: "John")!
        let smithRange = text.range(of: "Smith")!
        let spans = BIOSpanDecoder.decode(
            text: text,
            tokenRanges: [johnRange, smithRange],
            labels: ["B-PER", "I-PER"]
        )
        XCTAssertEqual(spans.count, 1)
        XCTAssertEqual(spans[0].label, "PER")
        XCTAssertEqual(spans[0].value, "John Smith")
    }

    func testSkipsOutsideLabels() {
        let text = "Hello world"
        let helloRange = text.range(of: "Hello")!
        let worldRange = text.range(of: "world")!
        let spans = BIOSpanDecoder.decode(
            text: text,
            tokenRanges: [helloRange, worldRange],
            labels: ["O", "B-LOC"]
        )
        XCTAssertEqual(spans.count, 1)
        XCTAssertEqual(spans[0].value, "world")
    }

    func testBIOESEndLabelContinuesAndClosesSpan() {
        let text = "John Smith met Bob"
        let johnRange = text.range(of: "John")!
        let smithRange = text.range(of: "Smith")!
        let bobRange = text.range(of: "Bob")!
        let spans = BIOSpanDecoder.decode(
            text: text,
            tokenRanges: [johnRange, smithRange, bobRange],
            labels: ["B-PER", "E-PER", "B-PER"]
        )
        XCTAssertEqual(spans.count, 2)
        XCTAssertEqual(spans[0].value, "John Smith", "E- must extend the open span before closing it")
        XCTAssertEqual(spans[1].value, "Bob")
    }

    func testBIOESEndLabelDoesNotAbsorbFollowingInsideLabel() {
        let text = "John Smith Junior"
        let johnRange = text.range(of: "John")!
        let smithRange = text.range(of: "Smith")!
        let juniorRange = text.range(of: "Junior")!
        let spans = BIOSpanDecoder.decode(
            text: text,
            tokenRanges: [johnRange, smithRange, juniorRange],
            labels: ["B-PER", "E-PER", "I-PER"]
        )
        XCTAssertEqual(spans.count, 2, "E- closes the span; a following I- starts a new one")
        XCTAssertEqual(spans[0].value, "John Smith")
        XCTAssertEqual(spans[1].value, "Junior")
    }

    func testBIOESSingleLabelEmitsStandaloneSpan() {
        let text = "visit Paris today"
        let parisRange = text.range(of: "Paris")!
        let visitRange = text.range(of: "visit")!
        let todayRange = text.range(of: "today")!
        let spans = BIOSpanDecoder.decode(
            text: text,
            tokenRanges: [visitRange, parisRange, todayRange],
            labels: ["O", "S-LOC", "O"]
        )
        XCTAssertEqual(spans.count, 1)
        XCTAssertEqual(spans[0].label, "LOC")
        XCTAssertEqual(spans[0].value, "Paris")
    }

    func testBIOESAdjacentSingleLabelsStaySeparate() {
        let text = "Paris Berlin"
        let parisRange = text.range(of: "Paris")!
        let berlinRange = text.range(of: "Berlin")!
        let spans = BIOSpanDecoder.decode(
            text: text,
            tokenRanges: [parisRange, berlinRange],
            labels: ["S-LOC", "S-LOC"]
        )
        XCTAssertEqual(spans.map(\.value), ["Paris", "Berlin"], "Each S- token is its own entity")
    }

    func testSpanConfidenceIsWorstCaseAcrossTokens() {
        let text = "John Smith"
        let johnRange = text.range(of: "John")!
        let smithRange = text.range(of: "Smith")!
        let spans = BIOSpanDecoder.decode(
            text: text,
            tokenRanges: [johnRange, smithRange],
            labels: ["B-PER", "E-PER"],
            confidences: [0.9, 0.6]
        )
        XCTAssertEqual(spans.first?.confidence, 0.6)
    }

    func testHandlesEmojiInRanges() {
        let text = "Meet 🎉Anna"
        guard let range = text.range(of: "🎉Anna") else {
            return XCTFail("Missing range")
        }
        let spans = BIOSpanDecoder.decode(
            text: text,
            tokenRanges: [range],
            labels: ["B-PER"]
        )
        XCTAssertEqual(spans.first?.value, "🎉Anna")
    }
}
