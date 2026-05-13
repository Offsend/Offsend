import KeyboardShortcuts
import SwiftUI

public struct SafePasteShortcutRecorder: View {
    private let title: String

    public init(title: String) {
        self.title = title
    }

    public var body: some View {
        KeyboardShortcuts.Recorder(title, name: .safePaste)
            .controlSize(.small)
    }
}

public struct RestorePlaceholdersShortcutRecorder: View {
    private let title: String

    public init(title: String) {
        self.title = title
    }

    public var body: some View {
        KeyboardShortcuts.Recorder(title, name: .restorePlaceholders)
            .controlSize(.small)
    }
}
