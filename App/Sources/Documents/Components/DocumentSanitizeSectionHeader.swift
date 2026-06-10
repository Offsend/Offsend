import AppUIKit
import SwiftUI

struct DocumentSanitizeSectionHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder let trailing: () -> Trailing

    init(title: String, @ViewBuilder trailing: @escaping () -> Trailing) {
        self.title = title
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .center, spacing: OFSpacing.sm) {
            Text(title.uppercased())
                .font(.system(size: 10.5, weight: .bold))
                .kerning(0.8)
                .foregroundColor(.ofTextMuted)
                .padding(.horizontal, 2)

            Spacer(minLength: 0)

            trailing()
        }
    }
}

extension DocumentSanitizeSectionHeader where Trailing == EmptyView {
    init(title: String) {
        self.title = title
        self.trailing = { EmptyView() }
    }
}
