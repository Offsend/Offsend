import CoreServices
import Foundation
import WorkspacePolicyCore

public final class WorkspaceWatchService {
    public struct Configuration: Sendable {
        public let debounceInterval: TimeInterval
        public let minAuditInterval: TimeInterval
        public let fsEventsLatency: TimeInterval

        public init(
            debounceInterval: TimeInterval,
            minAuditInterval: TimeInterval,
            fsEventsLatency: TimeInterval
        ) {
            self.debounceInterval = debounceInterval
            self.minAuditInterval = minAuditInterval
            self.fsEventsLatency = fsEventsLatency
        }
    }

    private let queue = DispatchQueue(label: "io.offsend.workspace-watch", qos: .utility)
    private let scheduler: WorkspaceWatchScheduling
    private let configuration: Configuration
    private var contexts: [UUID: RootWatchContext] = [:]
    private var rootsByID: [UUID: URL] = [:]
    private var auditConfiguration: AIWorkspacePrivacyAuditConfiguration?
    private var onAuditRequested: (@Sendable (UUID, URL, Set<String>) -> Void)?

    private struct RootWatchContext {
        var stream: FSEventStreamRef?
        let url: URL
        let debouncer: WorkspaceWatchAuditDebouncer
    }

    private final class StreamCallbackContext {
        weak var service: WorkspaceWatchService?
        let watchID: UUID

        init(service: WorkspaceWatchService, watchID: UUID) {
            self.service = service
            self.watchID = watchID
        }
    }

    public init(configuration: Configuration) {
        self.configuration = configuration
        scheduler = DispatchQueueWatchScheduler(queue: queue)
    }

    deinit {
        stopWatching()
    }

    public func startWatching(
        roots: [(id: UUID, url: URL)],
        configuration: AIWorkspacePrivacyAuditConfiguration,
        onAuditRequested: @escaping @Sendable (UUID, URL, Set<String>) -> Void
    ) {
        queue.sync {
            stopWatchingOnQueue()
            auditConfiguration = configuration
            self.onAuditRequested = onAuditRequested
            rootsByID = Dictionary(uniqueKeysWithValues: roots.map { ($0.id, $0.url) })
            for (id, url) in roots {
                startStreamOnQueue(id: id, url: url)
            }
        }
    }

    public func stopWatching() {
        queue.sync {
            stopWatchingOnQueue()
        }
    }

    private func stopWatchingOnQueue() {
        for (id, ctx) in contexts {
            tearDownStream(ctx)
            ctx.url.stopAccessingSecurityScopedResource()
            contexts.removeValue(forKey: id)
        }
        rootsByID.removeAll()
        auditConfiguration = nil
        onAuditRequested = nil
    }

    private func startStreamOnQueue(id: UUID, url: URL) {
        let callbackContext = StreamCallbackContext(service: self, watchID: id)
        var streamContext = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passRetained(callbackContext).toOpaque(),
            retain: nil,
            release: { info in
                guard let info else { return }
                Unmanaged<StreamCallbackContext>.fromOpaque(info).release()
            },
            copyDescription: nil
        )

        let callback: FSEventStreamCallback = { _, info, _, eventPaths, _, _ in
            guard let info else { return }
            let context = Unmanaged<StreamCallbackContext>.fromOpaque(info).takeUnretainedValue()
            let paths = unsafeBitCast(eventPaths, to: NSArray.self) as? [String] ?? []
            context.service?.handleFSEvents(watchID: context.watchID, absolutePaths: paths)
        }

        let paths = [url.path] as CFArray
        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &streamContext,
            paths,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            configuration.fsEventsLatency,
            UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagNoDefer)
        ) else {
            return
        }

        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)

        let debouncer = WorkspaceWatchAuditDebouncer(
            debounceInterval: configuration.debounceInterval,
            minAuditInterval: configuration.minAuditInterval,
            scheduler: scheduler
        ) { [weak self] changedPaths in
            self?.fireAuditRequest(watchID: id, url: url, changedPaths: changedPaths)
        }

        contexts[id] = RootWatchContext(
            stream: stream,
            url: url,
            debouncer: debouncer
        )
    }

    private func handleFSEvents(watchID: UUID, absolutePaths: [String]) {
        guard let ctx = contexts[watchID], let auditConfiguration else { return }

        let relevant = WorkspaceWatchRelevantPathFilter.relevantChangedPaths(
            absolutePaths: absolutePaths,
            rootURL: ctx.url,
            configuration: auditConfiguration
        )
        guard !relevant.isEmpty else { return }

        ctx.debouncer.noteChanges(relevant)
    }

    private func fireAuditRequest(watchID: UUID, url: URL, changedPaths: Set<String>) {
        guard let callback = onAuditRequested else { return }
        DispatchQueue.main.async {
            callback(watchID, url, changedPaths)
        }
    }

    private func tearDownStream(_ ctx: RootWatchContext) {
        ctx.debouncer.cancel()
        guard let stream = ctx.stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
    }
}
