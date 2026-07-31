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
    public let values: [String]

    public init(icon: String, label: String, count: Int, severity: OFEntitySeverity, values: [String] = []) {
        self.icon = icon
        self.label = label
        self.count = count
        self.severity = severity
        self.values = values
    }
}

public struct OFCategoryRow: View {
    private let entity: OFDetectedEntity
    private let isOn: Binding<Bool>?

    @State private var isExpanded = false

    public init(entity: OFDetectedEntity, isOn: Binding<Bool>? = nil) {
        self.entity = entity
        self.isOn = isOn
    }

    private var isExpandable: Bool {
        entity.values.count > 1
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: entity.icon)
                    .font(.system(size: 12))
                    .foregroundColor(severityColor)
                    .frame(width: 26, height: 26)
                    .background(severityBackground)
                    .cornerRadius(6)

                VStack(alignment: .leading, spacing: 2) {
                    Text(entity.label)
                        .font(.system(size: 13))
                        .foregroundColor(.ofText)

                    if !isExpanded, let firstValue = entity.values.first {
                        Text(firstValue)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.ofTextSub)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }

                Spacer(minLength: 8)

                countBadge

                if let isOn {
                    Toggle("", isOn: isOn)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .tint(severityColor)
                }
            }

            if isExpanded {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(Array(entity.values.enumerated()), id: \.offset) { _, value in
                        Text(value)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.ofTextSub)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.leading, 34)
                .padding(.top, 2)
            }
        }
        .padding(.vertical, 4)
        .opacity(isOn?.wrappedValue == false ? 0.5 : 1)
    }

    @ViewBuilder
    private var countBadge: some View {
        let content = HStack(spacing: 3) {
            Text("\(entity.count)")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(severityColor)

            if isExpandable {
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundColor(severityColor)
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
        .background(severityBackground)
        .clipShape(Capsule())

        if isExpandable {
            Button {
                isExpanded.toggle()
            } label: {
                content
            }
            .buttonStyle(.plain)
        } else {
            content
        }
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
