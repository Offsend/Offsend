import SwiftUI

public struct OFSelectOption<V: Hashable>: Hashable {
    public let value: V
    public let label: String
    public let detail: String?
    public let isEnabled: Bool

    public init(value: V, label: String, detail: String? = nil, isEnabled: Bool = true) {
        self.value = value
        self.label = label
        self.detail = detail
        self.isEnabled = isEnabled
    }
}

public struct OFSelectMenu<V: Hashable>: View {
    @Binding private var selection: V
    private let options: [OFSelectOption<V>]
    private let width: CGFloat?
    @Environment(\.ofPalette) private var palette
    @Environment(\.isEnabled) private var isEnabled

    public init(selection: Binding<V>, options: [OFSelectOption<V>], width: CGFloat? = nil) {
        self._selection = selection
        self.options = options
        self.width = width
    }

    public var body: some View {
        Menu {
            ForEach(options, id: \.self) { option in
                Button {
                    selection = option.value
                } label: {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(option.label)
                                .foregroundColor(option.isEnabled ? .primary : .secondary)
                            if let detail = option.detail {
                                Text(detail)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer(minLength: 12)
                        if selection == option.value {
                            Image(systemName: "checkmark")
                        }
                    }
                }
                .disabled(!option.isEnabled)
            }
        } label: {
            HStack(spacing: 8) {
                Text(options.first { $0.value == selection }?.label ?? "")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(isEnabled ? palette.text : palette.textMuted)
                Spacer(minLength: 8)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(isEnabled ? palette.textSub : palette.textMuted)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(width: width)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isEnabled ? palette.bg2 : palette.bg1)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(isEnabled ? palette.border2 : palette.border, lineWidth: 1))
            )
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}
