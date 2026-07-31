import SwiftUI

public enum OFStatusBadgeStyle {
    case pass
    case fail
    case warn
    case info
    case ok

    public var title: String {
        switch self {
        case .pass:
            return "PASS"
        case .fail:
            return "FAIL"
        case .warn:
            return "WARN"
        case .info:
            return "INFO"
        case .ok:
            return "OK"
        }
    }

    var countLabel: String {
        switch self {
        case .ok:
            return "ok"
        default:
            return title.lowercased()
        }
    }

    var backgroundColor: Color {
        switch self {
        case .pass, .ok:
            return .ofGreenDim
        case .fail:
            return .ofRedDim
        case .warn:
            return .ofAmberDim
        case .info:
            return .ofBlueDim
        }
    }

    var textColor: Color {
        switch self {
        case .pass, .ok:
            return .ofGreenText
        case .fail:
            return .ofRedText
        case .warn:
            return .ofAmberText
        case .info:
            return .ofBlueText
        }
    }
}

public struct OFStatusBadge: View {
    private let style: OFStatusBadgeStyle
    private let title: String
    private let compact: Bool

    public init(style: OFStatusBadgeStyle, title: String? = nil, compact: Bool = false) {
        self.style = style
        self.title = title ?? style.title
        self.compact = compact
    }

    public var body: some View {
        Text(title)
            .font(.system(size: compact ? 9 : 10, weight: .bold, design: .monospaced))
            .tracking(0.5)
            .foregroundColor(style.textColor)
            .padding(.horizontal, compact ? 6 : 8)
            .padding(.vertical, compact ? 2 : 3)
            .background(style.backgroundColor)
            .cornerRadius(OFRadius.sm)
            .overlay(
                RoundedRectangle(cornerRadius: OFRadius.sm)
                    .stroke(style.textColor.opacity(0.35), lineWidth: 1)
            )
            .frame(minWidth: compact ? 44 : 52)
    }
}

public struct OFStatusCapsule: View {
    private let style: OFStatusBadgeStyle
    private let title: String

    public init(style: OFStatusBadgeStyle, title: String) {
        self.style = style
        self.title = title
    }

    public var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .bold))
            .foregroundColor(style.textColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(style.backgroundColor)
            .clipShape(Capsule())
    }
}

public struct OFCountPill: View {
    private let count: Int
    private let style: OFStatusBadgeStyle

    public init(count: Int, style: OFStatusBadgeStyle) {
        self.count = count
        self.style = style
    }

    public var body: some View {
        Text("\(count) \(style.countLabel)")
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(style.textColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(style.backgroundColor)
            .clipShape(Capsule())
    }
}
