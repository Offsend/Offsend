import Foundation

public enum CheckFailPolicy: String, Sendable, CaseIterable {
    case block
    case warn
    case none
}
