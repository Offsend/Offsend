import AppUIKit
import CoreGraphics
import DetectionCore
import DocumentCore
import Foundation

enum DocumentSanitizeLayout {
    static let findingsContentWidth: CGFloat = 320
    static let documentPreviewMinWidth: CGFloat = 390
    static let interColumnSpacing: CGFloat = OFSpacing.lg
    static let horizontalInset: CGFloat = OFSpacing.xxl * 2
    static let windowWidth: CGFloat = findingsContentWidth + documentPreviewMinWidth + interColumnSpacing + horizontalInset
    static let footerHeight: CGFloat = 64
    static let awaitingResultHeight: CGFloat = 280
    static let findingsResultHeight: CGFloat = 520
    static let pdfPreviewMinHeight: CGFloat = 420
    static let documentTabBarHeight: CGFloat = 40
    static let batchProgressHeight: CGFloat = 22
    static let maskedPreviewCopyButtonReserve: CGFloat = 44
    /// Extra vertical room for body padding, section spacing, and footer chrome.
    static let contentVerticalSlack: CGFloat = OFSpacing.lg + OFSpacing.md
    static let tabSectionSpacing: CGFloat = OFSpacing.lg
}

struct DocumentBatchAnalysisProgress: Equatable {
    let finishedCount: Int
    let totalCount: Int
}

enum DocumentSanitizeWorkingOverlayMode: Equatable {
    case analyzing
    case sanitizing
    case refreshingPreview
}

enum DocumentBatchTabStatus: Equatable {
    case pending
    case analyzing
    case safe
    case findings(count: Int)
    case error
    case tooLarge
}

enum DocumentSanitizeWindowContentPhase {
    case awaitingResult
    case findingsResult
}

struct DocumentSanitizeEntityGroup: Identifiable {
    var id: SensitiveEntityType { type }
    let type: SensitiveEntityType
    let entities: [SensitiveEntity]
    let entityIDs: Set<UUID>

    init(type: SensitiveEntityType, entities: [SensitiveEntity]) {
        self.type = type
        self.entities = entities
        self.entityIDs = Set(entities.map(\.id))
    }
}

enum DocumentSanitizeEntityGrouping {
    static func groups(for result: DocumentAnalysisResult) -> [DocumentSanitizeEntityGroup] {
        Dictionary(grouping: result.detection.entities, by: \.type)
            .map { type, entities in
                DocumentSanitizeEntityGroup(
                    type: type,
                    entities: entities.sorted { $0.range.lowerBound < $1.range.lowerBound }
                )
            }
            .sorted { $0.type.rawValue < $1.type.rawValue }
    }
}
