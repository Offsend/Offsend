import AppKit
import Foundation

enum PrepareImportAlert {
    @MainActor
    static func presentUnsupported(urls: [URL]) {
        guard !urls.isEmpty else { return }

        let alert = NSAlert()
        alert.messageText = OffsendStrings.alertPrepareUnsupportedTitle
        alert.informativeText = informativeText(for: urls)
        alert.alertStyle = .warning
        alert.addButton(withTitle: OffsendStrings.alertDismiss)
        alert.runModal()
    }

    private static func informativeText(for urls: [URL]) -> String {
        if urls.count == 1 {
            return OffsendStrings.alertPrepareUnsupportedMessage(displayName(for: urls[0]))
        }
        let names = urls.map(displayName(for:)).joined(separator: ", ")
        return OffsendStrings.alertPrepareUnsupportedMessageMultiple(urls.count, names)
    }

    private static func displayName(for url: URL) -> String {
        url.lastPathComponent
    }
}
