import SwiftUI

public struct OFSegmentedOption<V: Hashable>: Hashable {
    public let value: V
    public let label: String

    public init(value: V, label: String) {
        self.value = value
        self.label = label
    }
}

public struct OFSegmentedControl<V: Hashable>: View {
    @Binding private var selection: V
    private let options: [OFSegmentedOption<V>]
    @Environment(\.ofPalette) private var palette

    public init(selection: Binding<V>, options: [OFSegmentedOption<V>]) {
        self._selection = selection
        self.options = options
    }

    public var body: some View {
        HStack(spacing: 1) {
            ForEach(options, id: \.self) { opt in
                Button {
                    selection = opt.value
                } label: {
                    Text(opt.label)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(selection == opt.value ? palette.text : palette.textSub)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 5)
                                .fill(selection == opt.value ? palette.bg0 : .clear)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 5)
                                        .stroke(selection == opt.value ? palette.border2 : .clear, lineWidth: 1)
                                )
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(palette.bg2)
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(palette.border, lineWidth: 1))
        )
    }
}
