import AppUIKit
import CoreGraphics
import Foundation

enum DirectoryCheckLayout {
    static let windowWidth: CGFloat = 640
    static let emptyStateHeight: CGFloat = 320
    static let resultStateHeight: CGFloat = 780
}

struct DirectoryCheckAuditSettings: Equatable {
    let disabledRuleIDs: Set<String>
    let extraSkippedDirectories: [String]
    let customIgnoreTemplate: String?
}

enum DirectoryCheckDisplayStatus: Equatable {
    case pass
    case fail
    case info
}

struct DirectoryCheckIssueCounts {
    let fail: Int
    let info: Int
    let ok: Int
}

struct DirectoryCheckFixApplySummary: Equatable {
    let patternFixCount: Int
    let fileCount: Int
    let createsNewFilesOnly: Bool
    let updatesExistingFiles: Bool
}

enum DirectoryCheckFindingTag {
    case pass
    case fail
    case warn
    case info

    var badgeStyle: OFStatusBadgeStyle {
        switch self {
        case .pass:
            return .pass
        case .fail:
            return .fail
        case .warn:
            return .warn
        case .info:
            return .info
        }
    }
}
