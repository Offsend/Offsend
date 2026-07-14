import Foundation
import OffsendRuntime
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

enum CLIStdin {
    enum ReadError: Error {
        case tty
        case readFailed
        case tooLarge(maxBytes: Int)
        case invalidUTF8

        var message: String {
            switch self {
            case .tty:
                return "Provide prompt text or hook JSON on stdin."
            case .readFailed:
                return "Failed to read stdin."
            case .tooLarge(let maxBytes):
                return "stdin exceeds \(maxBytes) bytes."
            case .invalidUTF8:
                return "stdin is not valid UTF-8."
            }
        }

        var failOpenReason: FailOpenReason {
            switch self {
            case .tty:
                return .stdinUnavailable
            case .readFailed:
                return .stdinReadFailed
            case .tooLarge:
                return .stdinTooLarge
            case .invalidUTF8:
                return .invalidUTF8
            }
        }
    }

    static var isInteractive: Bool {
        isatty(STDIN_FILENO) != 0
    }

    static func readData(maxBytes: Int = CheckHookLimits.maxStdinBytes) throws -> Data {
        if isInteractive {
            throw ReadError.tty
        }

        var data = Data()
        while true {
            var buffer = [UInt8](repeating: 0, count: 64 * 1024)
            let count = read(STDIN_FILENO, &buffer, buffer.count)
            if count < 0 {
                throw ReadError.readFailed
            }
            if count == 0 { break }
            data.append(contentsOf: buffer.prefix(count))
            if data.count > maxBytes {
                throw ReadError.tooLarge(maxBytes: maxBytes)
            }
        }
        return data
    }

    static func readUTF8(maxBytes: Int = CheckHookLimits.maxStdinBytes) throws -> String {
        let data = try readData(maxBytes: maxBytes)
        guard let text = String(data: data, encoding: .utf8) else {
            throw ReadError.invalidUTF8
        }
        return text
    }
}
