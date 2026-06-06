import Foundation

/// Cancellable handle for a scheduled piece of work.
protocol WorkspaceWatchTimerToken: AnyObject {
    func cancel()
}

/// Abstracts the clock and delayed execution so the debounce/throttle logic can be
/// driven deterministically in tests (no real wall-clock waits).
protocol WorkspaceWatchScheduling {
    func now() -> Date
    func schedule(after interval: TimeInterval, _ work: @escaping () -> Void) -> WorkspaceWatchTimerToken
}

/// Coalesces a burst of file-system changes into a single audit request (debounce)
/// and enforces a minimum spacing between audits (throttle).
///
/// Not thread-safe: all methods, and the work scheduled via the injected scheduler,
/// must run on a single serial execution context (the service's FSEvents queue).
final class WorkspaceWatchAuditDebouncer {
    private let debounceInterval: TimeInterval
    private let minAuditInterval: TimeInterval
    private let scheduler: WorkspaceWatchScheduling
    private let onFire: (Set<String>) -> Void

    private var pendingChangedPaths: Set<String> = []
    private var prefersImmediateFirePending = false
    private var lastFiredAt: Date?
    private var timer: WorkspaceWatchTimerToken?

    init(
        debounceInterval: TimeInterval,
        minAuditInterval: TimeInterval,
        scheduler: WorkspaceWatchScheduling,
        onFire: @escaping (Set<String>) -> Void
    ) {
        self.debounceInterval = debounceInterval
        self.minAuditInterval = minAuditInterval
        self.scheduler = scheduler
        self.onFire = onFire
    }

    func noteChanges(_ paths: Set<String>, prefersImmediateFire: Bool = false) {
        guard !paths.isEmpty else { return }
        pendingChangedPaths.formUnion(paths)
        if prefersImmediateFire {
            prefersImmediateFirePending = true
        }
        scheduleDebounce()
    }

    func cancel() {
        timer?.cancel()
        timer = nil
    }

    private func scheduleDebounce() {
        timer?.cancel()
        timer = scheduler.schedule(after: debounceInterval) { [weak self] in
            self?.attemptFire()
        }
    }

    private func attemptFire() {
        let now = scheduler.now()
        if !prefersImmediateFirePending, let last = lastFiredAt {
            let elapsed = now.timeIntervalSince(last)
            if elapsed < minAuditInterval {
                timer?.cancel()
                timer = scheduler.schedule(after: minAuditInterval - elapsed) { [weak self] in
                    self?.attemptFire()
                }
                return
            }
        }

        let paths = pendingChangedPaths
        lastFiredAt = now
        pendingChangedPaths = []
        prefersImmediateFirePending = false
        timer = nil
        onFire(paths)
    }
}

/// Production scheduler backed by a serial `DispatchQueue`.
final class DispatchQueueWatchScheduler: WorkspaceWatchScheduling {
    private let queue: DispatchQueue

    init(queue: DispatchQueue) {
        self.queue = queue
    }

    func now() -> Date {
        Date()
    }

    func schedule(after interval: TimeInterval, _ work: @escaping () -> Void) -> WorkspaceWatchTimerToken {
        let item = DispatchWorkItem(block: work)
        queue.asyncAfter(deadline: .now() + interval, execute: item)
        return DispatchWorkItemToken(item)
    }

    private final class DispatchWorkItemToken: WorkspaceWatchTimerToken {
        private let item: DispatchWorkItem

        init(_ item: DispatchWorkItem) {
            self.item = item
        }

        func cancel() {
            item.cancel()
        }
    }
}
