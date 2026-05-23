import SwiftUI

public struct OFSelectOption<V: Hashable>: Hashable {
    public let value: V
    public let label: String
    public let detail: String?

    public init(value: V, label: String, detail: String? = nil) {
        self.value = value
        self.label = label
        self.detail = detail
    }
}

public struct OFSelectMenu<V: Hashable>: View {
    @Binding private var selection: V
    private let options: [OFSelectOption<V>]
    private let width: CGFloat?
    @Environment(\.ofPalette) private var palette

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
            }
        } label: {
            HStack(spacing: 8) {
                Text(options.first { $0.value == selection }?.label ?? "")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(palette.text)
                Spacer(minLength: 8)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(palette.textSub)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(width: width)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(palette.bg2)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(palette.border2, lineWidth: 1))
            )
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}
