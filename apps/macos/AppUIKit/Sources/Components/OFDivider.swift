import SwiftUI

public struct OFDivider: View {
    public init() {}

    public var body: some View {
        Divider()
            .overlay(Color.ofBorder)
    }
}
