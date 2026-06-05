import AppUIKit
import SwiftUI

struct DirectoryCheckSectionHeader: View {
    let title: String

    var body: some View {
        Text(title.uppercased())
            .font(.system(size: 10.5, weight: .bold))
            .kerning(0.8)
            .foregroundColor(.ofTextMuted)
            .padding(.horizontal, 2)
    }
}
