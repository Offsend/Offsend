import XCTest
@testable import DetectionCore

final class AIModelSessionManagerTests: XCTestCase {
    func testBeginSessionCancelsPendingUnload() async {
        let exp = expectation(description: "unload")
        exp.isInverted = true

        let manager = AIModelSessionManager(idleUnloadInterval: 0.1, onUnload: { exp.fulfill() })
        manager.beginSession()
        manager.endSession()
        manager.beginSession()

        await fulfillment(of: [exp], timeout: 0.25)
    }

    func testEndSessionSchedulesUnloadWhenLastSessionEnds() async {
        let exp = expectation(description: "unload")

        let manager = AIModelSessionManager(idleUnloadInterval: 0.05, onUnload: { exp.fulfill() })
        manager.beginSession()
        manager.endSession()

        await fulfillment(of: [exp], timeout: 0.5)
    }

    func testNestedSessionsDelayUnloadUntilAllEnd() async {
        let exp = expectation(description: "unload")

        let manager = AIModelSessionManager(idleUnloadInterval: 0.2, onUnload: { exp.fulfill() })
        manager.beginSession()
        manager.beginSession()
        manager.endSession()

        try? await Task.sleep(for: .milliseconds(100))
        manager.endSession()

        await fulfillment(of: [exp], timeout: 0.5)
    }

    func testScheduleUnloadIfIdleOnlyWhenNoSessions() async {
        let exp = expectation(description: "unload")

        let manager = AIModelSessionManager(idleUnloadInterval: 0.05, onUnload: { exp.fulfill() })
        manager.beginSession()
        manager.scheduleUnloadIfIdle()
        manager.endSession()

        await fulfillment(of: [exp], timeout: 0.5)
    }
}
