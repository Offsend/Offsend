import SwiftUI

public struct OFRiskMeterBar: View {
    private let risk: OFRiskLevel
    private let score: Int
    private let totalBars: Int

    public init(risk: OFRiskLevel, score: Int, totalBars: Int = 10) {
        self.risk = risk
        self.score = min(max(score, 0), 100)
        self.totalBars = max(totalBars, 1)
    }

    private var filledBarCount: Int {
        if score == 0 {
            return 1
        }
        let pointsPerBar = 100.0 / Double(totalBars)
        return min(totalBars, Int(ceil(Double(score) / pointsPerBar)))
    }

    public var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<totalBars, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2)
                    .fill(index < filledBarCount ? risk.accentColor : Color.ofBg3)
                    .frame(height: 3)
            }

            Text("\(score) / 100")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.ofTextMuted)
                .fixedSize()
        }
        .animation(.easeInOut(duration: 0.3), value: filledBarCount)
        .animation(.easeInOut(duration: 0.3), value: risk)
    }
}
