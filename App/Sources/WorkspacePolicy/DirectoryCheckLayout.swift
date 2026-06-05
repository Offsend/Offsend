import AppUIKit
import CoreGraphics
import Foundation

enum DirectoryCheckLayout {
    static let windowWidth: CGFloat = 640
    static let emptyStateHeight: CGFloat = 320
    static let resultStateHeight: CGFloat = 860
    static let freeBannerExtra: CGFloat = 88
}

struct DirectoryCheckAuditSettings: Equatable {
    let disabledRuleIDs: Set<String>
    let extraSkippedDirectories: [String]
    let customIgnoreTemplate: String?
}

struct DirectoryCheckIssueCounts {
    let fail: Int
    let warn: Int
    let ok: Int

    var totalIssues: Int { fail + warn }
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
