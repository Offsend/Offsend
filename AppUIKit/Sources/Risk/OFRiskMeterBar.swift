import SwiftUI

public struct OFRiskMeterBar: View {
    private let risk: OFRiskLevel
    private let score: Int
    private let totalBars = 5

    public init(risk: OFRiskLevel, score: Int) {
        self.risk = risk
        self.score = score
    }

    public var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<totalBars, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2)
                    .fill(index < risk.filledBars ? risk.accentColor : Color.ofBg3)
                    .frame(height: 3)
                    .animation(.easeInOut(duration: 0.3), value: risk.filledBars)
            }

            Text("\(score) / 100")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.ofTextMuted)
                .fixedSize()
        }
    }
}
