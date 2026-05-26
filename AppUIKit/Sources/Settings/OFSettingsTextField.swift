import SwiftUI

public struct OFSettingsTextField: View {
    @Binding private var text: String
    private let prompt: Text
    private let width: CGFloat
    private let monospaced: Bool
    @Environment(\.ofPalette) private var palette
    @Environment(\.isEnabled) private var isEnabled

    public init(text: Binding<String>, prompt: Text, width: CGFloat = 240, monospaced: Bool = false) {
        self._text = text
        self.prompt = prompt
        self.width = width
        self.monospaced = monospaced
    }

    public var body: some View {
        TextField("", text: $text, prompt: prompt)
            .textFieldStyle(.plain)
            .font(.system(size: 12, design: monospaced ? .monospaced : .default))
            .foregroundColor(isEnabled ? palette.text : palette.textMuted)
            .frame(width: width)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isEnabled ? palette.bg2 : palette.bg1)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(isEnabled ? palette.border2 : palette.border, lineWidth: 1))
            )
    }
}
