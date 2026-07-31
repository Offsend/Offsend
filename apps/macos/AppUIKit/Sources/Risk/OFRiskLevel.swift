import SwiftUI

public enum OFRiskLevel {
    case none
    case medium
    case critical

    public var accentColor: Color {
        switch self {
        case .none:
            return .ofGreen
        case .medium:
            return .ofAmber
        case .critical:
            return .ofRed
        }
    }

    public var dimColor: Color {
        switch self {
        case .none:
            return .ofGreenDim
        case .medium:
            return .ofAmberDim
        case .critical:
            return .ofRedDim
        }
    }

    public var textColor: Color {
        switch self {
        case .none:
            return .ofGreenText
        case .medium:
            return .ofAmberText
        case .critical:
            return .ofRedText
        }
    }

    public var label: String {
        switch self {
        case .none:
            return AppUIKitStrings.riskSafe
        case .medium:
            return AppUIKitStrings.riskMedium
        case .critical:
            return AppUIKitStrings.riskCritical
        }
    }

    public var filledBars: Int {
        switch self {
        case .none:
            return 0
        case .medium:
            return 3
        case .critical:
            return 5
        }
    }
}
