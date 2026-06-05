import AppUIKit
import SwiftUI

struct DirectoryCheckFreeScopeNote: View {
    var body: some View {
        HStack(alignment: .top, spacing: OFSpacing.sm) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 13))
                .foregroundColor(.ofBlue)
                .padding(.top, 1)

            Text(OffsendStrings.directoryCheckFreeScopeNote)
                .font(.system(size: 12))
                .foregroundColor(.ofTextSub)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(OFSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.ofBlueDim)
        .cornerRadius(OFRadius.md)
        .overlay(
            RoundedRectangle(cornerRadius: OFRadius.md)
                .stroke(Color.ofBlue.opacity(0.25), lineWidth: 1)
        )
    }
}
