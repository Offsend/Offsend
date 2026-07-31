import Foundation

public enum DocumentProcessingLimits {
    public static let freeMaximumFileByteCount = 15 * 1_024 * 1_024
    public static let proMaximumFileByteCount = 50 * 1_024 * 1_024

    public static func maximumFileByteCount(isPro: Bool) -> Int {
        isPro ? proMaximumFileByteCount : freeMaximumFileByteCount
    }
}
