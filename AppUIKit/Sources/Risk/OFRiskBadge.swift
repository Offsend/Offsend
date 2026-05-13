import SwiftUI

public struct OFRiskBadge: View {
    private let risk: OFRiskLevel

    public init(risk: OFRiskLevel) {
        self.risk = risk
    }

    public var body: some View {
        Text(risk.label.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .kerning(0.6)
            .foregroundColor(risk.textColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(risk.dimColor)
            .clipShape(Capsule())
    }
}
