import AppUIKit
import AppKit
import SwiftUI

@MainActor
final class ClipboardStatusPanelController {
    private let popover = NSPopover()

    init(title: String, message: String, score: Int, onClose: @escaping () -> Void) {
        let popover = self.popover
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 320, height: 190)
        popover.contentViewController = NSHostingController(
            rootView: ClipboardStatusPanelView(
                title: title,
                message: message,
                score: score,
                close: { [weak popover] in
                    popover?.performClose(nil)
                    onClose()
                }
            )
        )
    }

    func show(from statusItem: NSStatusItem) {
        if popover.isShown {
            popover.performClose(nil)
        }

        if let button = statusItem.button {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .maxY)
        }
    }
}

struct ClipboardStatusPanelView: View {
    let title: String
    let message: String
    let score: Int
    let close: () -> Void

    var body: some View {
        OFPanel(width: 320) {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top, spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.ofGreenDim)
                                .frame(width: 40, height: 40)

                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 20))
                                .foregroundColor(.ofGreen)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Text(title)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.ofText)

                                OFRiskBadge(risk: .none)
                            }

                            Text(message)
                                .font(.system(size: 12))
                                .foregroundColor(.ofTextSub)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    OFRiskMeterBar(risk: .none, score: score)
                }
                .padding(OFSpacing.xl)

                OFDivider()

                OFButton(title: OffsendStrings.safePasteActionCancel, variant: .ghost) {
                    close()
                }
                .padding(.horizontal, OFSpacing.xl)
                .padding(.vertical, OFSpacing.md)
            }
        }
    }
}
