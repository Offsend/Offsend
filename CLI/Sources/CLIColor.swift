import Foundation
import OffsendRuntime

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

enum CLIColor {
    /// Color for text output when format is text, stdout is a TTY, and NO_COLOR is unset.
    static func enabled(for format: CheckOutputFormat) -> Bool {
        format == .text
            && ProcessInfo.processInfo.environment["NO_COLOR"] == nil
            && isatty(STDOUT_FILENO) != 0
    }

    static var isInteractiveTTY: Bool {
        isatty(STDIN_FILENO) != 0 && isatty(STDERR_FILENO) != 0
    }
}
