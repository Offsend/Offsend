import XCTest
@testable import WorkspaceWatchService

final class WorkspaceWatchAuditDebouncerTests: XCTestCase {
    private func makeDebouncer(
        debounce: TimeInterval = 2,
        minInterval: TimeInterval = 30,
        scheduler: ManualScheduler,
        onFire: @escaping (Set<String>) -> Void
    ) -> WorkspaceWatchAuditDebouncer {
        WorkspaceWatchAuditDebouncer(
            debounceInterval: debounce,
            minAuditInterval: minInterval,
            scheduler: scheduler,
            onFire: onFire
        )
    }

    func testDebouncesBurstOfChangesIntoSingleFire() {
        let scheduler = ManualScheduler()
        var fires: [Set<String>] = []
        let debouncer = makeDebouncer(scheduler: scheduler) { fires.append($0) }

        debouncer.noteChanges([".cursorignore"])
        scheduler.advance(by: 1)
        debouncer.noteChanges([".aiexclude"]) // resets the debounce window
        scheduler.advance(by: 1)
        XCTAssertTrue(fires.isEmpty, "Debounce window must restart on each new change.")

        scheduler.advance(by: 1) // 2s after the last change

        XCTAssertEqual(fires, [[".cursorignore", ".aiexclude"]])
    }

    func testThrottlesSecondAuditToMinInterval() {
        let scheduler = ManualScheduler()
        var fires: [Set<String>] = []
        let debouncer = makeDebouncer(scheduler: scheduler) { fires.append($0) }

        debouncer.noteChanges(["a"])
        scheduler.advance(by: 2) // first audit at t=2
        XCTAssertEqual(fires, [["a"]])

        debouncer.noteChanges(["b"])
        scheduler.advance(by: 2) // t=4: debounce elapsed but only 2s since last audit
        XCTAssertEqual(fires.count, 1, "Second audit must be throttled until min interval passes.")

        scheduler.advance(by: 28) // t=32: 30s since last audit

        XCTAssertEqual(fires.count, 2)
        XCTAssertEqual(fires[1], ["b"])
    }

    func testChangesArrivingDuringThrottleWaitAreCoalescedIntoRetry() {
        let scheduler = ManualScheduler()
        var fires: [Set<String>] = []
        let debouncer = makeDebouncer(scheduler: scheduler) { fires.append($0) }

        debouncer.noteChanges(["a"])
        scheduler.advance(by: 2) // first audit at t=2
        debouncer.noteChanges(["b"])
        scheduler.advance(by: 2) // t=4: throttled
        debouncer.noteChanges(["c"]) // still within the wait

        scheduler.advance(by: 60)

        XCTAssertEqual(fires.count, 2)
        XCTAssertEqual(fires[1], ["b", "c"], "All changes seen during the throttle wait must be reported together.")
    }

    func testSensitiveChangesBypassMinIntervalThrottle() {
        let scheduler = ManualScheduler()
        var fires: [Set<String>] = []
        let debouncer = makeDebouncer(scheduler: scheduler) { fires.append($0) }

        debouncer.noteChanges([".cursorignore"])
        scheduler.advance(by: 2) // first audit at t=2
        debouncer.noteChanges(["cert.pem"], prefersImmediateFire: true)
        scheduler.advance(by: 2) // t=4: debounce only, no min-interval wait

        XCTAssertEqual(fires.count, 2)
        XCTAssertEqual(fires[1], ["cert.pem"])
    }

    func testCancelPreventsPendingFire() {
        let scheduler = ManualScheduler()
        var fires: [Set<String>] = []
        let debouncer = makeDebouncer(scheduler: scheduler) { fires.append($0) }

        debouncer.noteChanges(["a"])
        debouncer.cancel()
        scheduler.advance(by: 100)

        XCTAssertTrue(fires.isEmpty)
    }

    func testEmptyChangesNeverScheduleFire() {
        let scheduler = ManualScheduler()
        var fires: [Set<String>] = []
        let debouncer = makeDebouncer(scheduler: scheduler) { fires.append($0) }

        debouncer.noteChanges([])
        scheduler.advance(by: 100)

        XCTAssertTrue(fires.isEmpty)
    }
}

/// Deterministic scheduler with a virtual clock: tests advance time explicitly and
/// the scheduler runs due, non-cancelled work in chronological order.
private final class ManualScheduler: WorkspaceWatchScheduling {
    private var current: Date
    private var scheduled: [Scheduled] = []

    init(start: Date = Date(timeIntervalSince1970: 0)) {
        current = start
    }

    func now() -> Date {
        current
    }

    func schedule(after interval: TimeInterval, _ work: @escaping () -> Void) -> WorkspaceWatchTimerToken {
        let token = Token()
        scheduled.append(Scheduled(fireAt: current.addingTimeInterval(interval), token: token, work: work))
        return token
    }

    func advance(by interval: TimeInterval) {
        let target = current.addingTimeInterval(interval)

        while let next = scheduled
            .filter({ !$0.token.cancelled && $0.fireAt <= target })
            .min(by: { $0.fireAt < $1.fireAt }) {
            scheduled.removeAll { $0 === next }
            current = next.fireAt
            next.work()
        }

        current = target
        scheduled.removeAll { $0.token.cancelled }
    }

    private final class Scheduled {
        let fireAt: Date
        let token: Token
        let work: () -> Void

        init(fireAt: Date, token: Token, work: @escaping () -> Void) {
            self.fireAt = fireAt
            self.token = token
            self.work = work
        }
    }

    private final class Token: WorkspaceWatchTimerToken {
        var cancelled = false
        func cancel() { cancelled = true }
    }
}
