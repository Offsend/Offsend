import Foundation

public enum OffsendExitCode: Int32, Sendable {
    case success = 0
    case findings = 1
    case error = 2
    case hookState = 3
}
