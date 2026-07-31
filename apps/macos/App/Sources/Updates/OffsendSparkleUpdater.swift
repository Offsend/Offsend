import Foundation
import Sparkle

/// Retains `SPUStandardUpdaterController` for the app lifetime (Sparkle expects a long-lived instance).
@MainActor
final class OffsendSparkleUpdater {
    private let standardUpdaterController: SPUStandardUpdaterController

    init() {
        standardUpdaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    /// Triggers Sparkle’s explicit update check UI (pass `NSMenuItem` as `sender` for correct modality when available).
    func checkForUpdates(sender: Any?) {
        standardUpdaterController.checkForUpdates(sender)
    }
}
