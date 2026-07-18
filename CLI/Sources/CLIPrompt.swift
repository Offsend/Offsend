import Foundation
import OffsendRuntime

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

enum CLIPrompt {
    static var isInteractiveTTY: Bool { CLIColor.isInteractiveTTY }

    static func yesNo(question: String, hint: String? = nil, defaultYes: Bool) -> Bool {
        let ui = CLIText(useColor: ProcessInfo.processInfo.environment["NO_COLOR"] == nil && isatty(STDERR_FILENO) != 0)
        fputs("\(ui.palette.bold(question))\n", stderr)
        if let hint, !hint.isEmpty {
            fputs("  \(ui.hint(hint))\n", stderr)
        }
        let suffix = defaultYes ? "Y/n" : "y/N"
        fputs("[\(suffix)]: ", stderr)
        for _ in 1...3 {
            let line = readLine() ?? ""
            if let value = ProjectConfigTemplates.parseYesNo(line, defaultYes: defaultYes) {
                return value
            }
            fputs("Please answer y or n: ", stderr)
        }
        return defaultYes
    }

    static func line(prompt: String) -> String {
        fputs(prompt, stderr)
        return (readLine() ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func step(current: Int, total: Int, title: String) {
        let ui = CLIText(useColor: ProcessInfo.processInfo.environment["NO_COLOR"] == nil && isatty(STDERR_FILENO) != 0)
        fputs("\n\(ui.step(current: current, total: total, title: title))\n", stderr)
    }
}
