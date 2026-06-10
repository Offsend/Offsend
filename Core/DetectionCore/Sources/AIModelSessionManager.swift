import Foundation

/// Tracks active AI-detection consumers and unloads the model after an idle interval when none remain.
public final class AIModelSessionManager: @unchecked Sendable {
    public static let defaultIdleUnloadInterval: TimeInterval = 60

    private let lock = NSLock()
    private var activeSessions = 0
    private var unloadTask: Task<Void, Never>?
    private let idleUnloadInterval: TimeInterval
    private let onUnload: @Sendable () -> Void

    public init(
        idleUnloadInterval: TimeInterval = 60,
        onUnload: @escaping @Sendable () -> Void
    ) {
        self.idleUnloadInterval = idleUnloadInterval
        self.onUnload = onUnload
    }

    public var hasActiveSessions: Bool {
        lock.withLock { activeSessions > 0 }
    }

    public func beginSession() {
        lock.withLock {
            unloadTask?.cancel()
            unloadTask = nil
            activeSessions += 1
        }
    }

    public func endSession() {
        lock.withLock {
            activeSessions = max(0, activeSessions - 1)
            guard activeSessions == 0 else { return }
            scheduleUnloadLocked()
        }
    }

    /// Schedules unload when there are no active sessions (e.g. after a settings validation load).
    public func scheduleUnloadIfIdle() {
        lock.withLock {
            guard activeSessions == 0 else { return }
            scheduleUnloadLocked()
        }
    }

    public func cancelScheduledUnload() {
        lock.withLock {
            unloadTask?.cancel()
            unloadTask = nil
        }
    }

    private func scheduleUnloadLocked() {
        unloadTask?.cancel()
        unloadTask = Task { [idleUnloadInterval, onUnload] in
            try? await Task.sleep(for: .seconds(idleUnloadInterval))
            guard !Task.isCancelled else { return }
            onUnload()
        }
    }
}
