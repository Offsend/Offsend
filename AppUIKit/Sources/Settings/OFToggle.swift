import SwiftUI

public struct OFToggle: View {
    @Binding private var isOn: Bool
    private let size: CGFloat
    @Environment(\.ofPalette) private var palette

    public init(isOn: Binding<Bool>, size: CGFloat = 20) {
        self._isOn = isOn
        self.size = size
    }

    public var body: some View {
        let width: CGFloat = size == 20 ? 36 : 30
        let knob = size - 4
        Button {
            withAnimation(.easeInOut(duration: 0.18)) { isOn.toggle() }
        } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule()
                    .fill(isOn ? palette.blue : palette.bg3)
                    .frame(width: width, height: size)
                Circle()
                    .fill(Color.white)
                    .frame(width: knob, height: knob)
                    .shadow(color: .black.opacity(0.25), radius: 1, y: 1)
                    .padding(2)
            }
        }
        .buttonStyle(.plain)
    }
}
