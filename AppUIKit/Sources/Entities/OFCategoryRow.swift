import SwiftUI

public enum OFEntitySeverity {
    case low
    case medium
    case high
    case critical
}

public struct OFDetectedEntity: Identifiable {
    public let id = UUID()
    public let icon: String
    public let label: String
    public let count: Int
    public let severity: OFEntitySeverity

    public init(icon: String, label: String, count: Int, severity: OFEntitySeverity) {
        self.icon = icon
        self.label = label
        self.count = count
        self.severity = severity
    }
}

public struct OFCategoryRow: View {
    private let entity: OFDetectedEntity

    public init(entity: OFDetectedEntity) {
        self.entity = entity
    }

    public var body: some View {
        HStack(spacing: 8) {
            Image(systemName: entity.icon)
                .font(.system(size: 12))
                .foregroundColor(severityColor)
                .frame(width: 26, height: 26)
                .background(severityBackground)
                .cornerRadius(6)

            Text(entity.label)
                .font(.system(size: 13))
                .foregroundColor(.ofText)

            Spacer()

            Text("\(entity.count)")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(severityColor)
                .padding(.horizontal, 7)
                .padding(.vertical, 1)
                .background(severityBackground)
                .clipShape(Capsule())
        }
        .padding(.vertical, 4)
    }

    private var severityColor: Color {
        switch entity.severity {
        case .low:
            return .ofBlueText
        case .medium, .high:
            return .ofAmberText
        case .critical:
            return .ofRedText
        }
    }

    private var severityBackground: Color {
        switch entity.severity {
        case .low:
            return .ofBlueDim
        case .medium, .high:
            return .ofAmberDim
        case .critical:
            return .ofRedDim
        }
    }
}
