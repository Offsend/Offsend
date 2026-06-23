import Foundation

/// Animates a brand-themed spinner on stderr while work is in progress (interactive TTY only).
final class CLISpinner: @unchecked Sendable {
    private static let frames = ["   }   ", "＊  }   ", " ＊ }   ", "  ＊}   ", "＊  }·  ", " ＊ }·  ", "  ＊}·  ", "＊  }·· ", " ＊ }·· ", "  ＊}·· ", "   }···", "   } ··", "   }  ·"]
    
    private let message: String
    private let enabled: Bool
    private var animationTask: Task<Void, Never>?

    init(message: String, enabled: Bool = CLISpinner.shouldAnimate) {
        self.message = message
        self.enabled = enabled
    }

    static var shouldAnimate: Bool {
        isatty(STDERR_FILENO) != 0
    }

    func start() {
        guard enabled else { return }
        animationTask = Task {
            var index = 0
            while !Task.isCancelled {
                let frame = Self.frames[index % Self.frames.count]
                fputs("\r\(frame) \(message)", stderr)
                fflush(stderr)
                index += 1
                try? await Task.sleep(nanoseconds: 110_000_000)
            }
        }
    }

    func stop() {
        guard enabled else { return }
        animationTask?.cancel()
        animationTask = nil
        fputs("\u{001B}[2K\r", stderr)
        fflush(stderr)
    }

    func runWhile<T>(_ work: () throws -> T) rethrows -> T {
        start()
        defer { stop() }
        return try work()
    }

    func runWhile<T>(_ work: () async throws -> T) async rethrows -> T {
        start()
        defer { stop() }
        return try await work()
    }
}
