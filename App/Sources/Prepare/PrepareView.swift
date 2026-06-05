import AppKit
import AppUIKit
import DocumentCore
import SwiftUI
import UniformTypeIdentifiers

enum PrepareWindowChrome {
    /// Inset below traffic-light buttons when the prepare window uses a hidden title bar.
    static let contentTopInset: CGFloat = 0
    static let horizontalPadding: CGFloat = 0
    static let compactHeaderHeight: CGFloat = 48

    /// Matches `DocumentSanitizeContentView.Layout.windowWidth`.
    static let documentContentWidth: CGFloat = 782
    /// Matches `DirectoryCheckLayout.windowWidth`.
    static let directoryContentWidth: CGFloat = 640
    static let emptyContentWidth: CGFloat = documentContentWidth

    static func contentWidth(for selection: PrepareSelection?) -> CGFloat {
        switch selection {
        case .document:
            return documentContentWidth
        case .directory:
            return directoryContentWidth
        case nil:
            return emptyContentWidth
        }
    }

    static func windowWidth(contentWidth: CGFloat) -> CGFloat {
        contentWidth + horizontalPadding * 2
    }

    static func windowWidth(for selection: PrepareSelection?) -> CGFloat {
        windowWidth(contentWidth: contentWidth(for: selection))
    }

    static func windowHeight(bodyHeight: CGFloat, extraBottom: CGFloat = 0) -> CGFloat {
        contentTopInset + compactHeaderHeight + bodyHeight + extraBottom
    }
}

struct PrepareView: View {
    let prepareWindowPath: String?

    @EnvironmentObject private var coordinator: AppCoordinator
    @State private var selection: PrepareSelection?
    @State private var prepareSessionID = UUID()
    @State private var isDropTargeted = false
    @State private var windowResetToken = UUID()

    private enum Layout {
        static let windowWidth: CGFloat = 782
        static let emptyStateHeight: CGFloat = 400
    }

    var body: some View {
        OFChromeShell { palette in
            prepareShell(palette: palette)
        }
    }

    @ViewBuilder
    private func prepareShell(palette: OFPalette) -> some View {
        let shellWidth = PrepareWindowChrome.windowWidth(for: selection)
        let emptyWindowSize = NSSize(
            width: shellWidth,
            height: PrepareWindowChrome.windowHeight(
                bodyHeight: Layout.emptyStateHeight,
                extraBottom: OFSpacing.md
            )
        )

        VStack(spacing: 0) {
            prepareHeader

            if let selection {
                switch selection {
                case let .document(fileURL):
                    DocumentSanitizeContentView(
                        fileURL: fileURL,
                        onReplaceSelection: applyReplacement(from:)
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .id(fileURL)
                case let .directory(directoryURL):
                    DirectoryCheckContentView(
                        directoryURL: directoryURL,
                        onReplaceSelection: applyReplacement(from:)
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .id(directoryURL)
                }
            } else {
                emptyDropZone
                    .padding(.horizontal, OFSpacing.md)
                    .padding(.bottom, OFSpacing.md)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .id(prepareSessionID)
        .padding(.top, PrepareWindowChrome.contentTopInset)
        .padding(.horizontal, PrepareWindowChrome.horizontalPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .frame(minWidth: shellWidth, minHeight: selection == nil ? emptyWindowSize.height : nil)
        .background(palette.bg1)
        .background {
            if selection == nil {
                PrepareWindowConfigurator(
                    minimumSize: emptyWindowSize,
                    preferredSize: emptyWindowSize,
                    resetToken: windowResetToken
                )
            }
        }
        .onAppear {
            windowResetToken = UUID()
            prefillFromPasteboardIfNeeded()
            bootstrapFromWindowPathIfNeeded()
        }
        .onDisappear(perform: releasePrepareSession)
        .onChange(of: prepareWindowPath) { _ in
            bootstrapFromWindowPathIfNeeded()
        }
        .dismissOnWindowCloseButton(onWillClose: releasePrepareSession)
    }

    private func releasePrepareSession() {
        selection = nil
        prepareSessionID = UUID()
        windowResetToken = UUID()
    }

    private var prepareHeader: some View {
        HStack(alignment: .center, spacing: OFSpacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text(OffsendStrings.prepareTitle)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.ofText)

                Text(OffsendStrings.prepareSubtitle)
                    .font(.system(size: 11))
                    .foregroundColor(.ofTextMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: OFSpacing.sm)

            OFButton(
                title: OffsendStrings.prepareChoose,
                variant: .outline,
                icon: "plus",
                small: true
            ) {
                chooseItem()
            }
        }
        .padding(.bottom, OFSpacing.xl)
        .padding(.horizontal, OFSpacing.md)
    }

    private var emptyDropZone: some View {
        OFDropZone(
            title: OffsendStrings.prepareDropTitle,
            hint: prepareDropHint,
            isTargeted: isDropTargeted,
            fillsAvailableSpace: true
        ) {
            chooseItem()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers)
        }
    }

    private var prepareDropHint: String {
        guard !coordinator.isProEntitlementActive else {
            return OffsendStrings.prepareDropHint
        }
        let freeLimit = Self.formattedMegabytes(DocumentProcessingLimits.freeMaximumFileByteCount)
        let proLimit = Self.formattedMegabytes(DocumentProcessingLimits.proMaximumFileByteCount)
        return OffsendStrings.prepareDropHintWithFileSizeLimit(freeLimit, proLimit)
    }

    private func applyReplacement(from url: URL) {
        guard let replacement = PrepareURLClassification.selection(for: url) else { return }
        selection = replacement
    }

    private func bootstrapFromWindowPathIfNeeded() {
        guard let prepareWindowPath,
              let resolved = PrepareURLClassification.selection(forWindowPath: prepareWindowPath) else {
            return
        }
        guard selection?.url.standardizedFileURL != resolved.url.standardizedFileURL else { return }
        selection = resolved
    }

    private func prefillFromPasteboardIfNeeded() {
        guard selection == nil, let resolved = PrepareURLClassification.selectionFromPasteboard() else {
            return
        }
        selection = resolved
    }

    private func chooseItem() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.prompt = OffsendStrings.prepareChoose

        guard panel.runModal() == .OK, let url = panel.url else { return }
        applyReplacement(from: url)
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }) else {
            return false
        }

        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            guard let url = Self.fileURL(from: item),
                  let resolved = PrepareURLClassification.selection(for: url) else {
                return
            }

            DispatchQueue.main.async {
                if self.selection != nil {
                    self.coordinator.openPrepare(for: resolved.url, source: "prepare_drop")
                } else {
                    self.selection = resolved
                }
            }
        }
        return true
    }

    private static func formattedMegabytes(_ bytes: Int) -> String {
        let megabytes = Double(bytes) / (1024 * 1024)
        if megabytes >= 10 {
            return String(format: "%.0f MB", megabytes)
        }
        return String(format: "%.1f MB", megabytes)
    }

    nonisolated private static func fileURL(from item: NSSecureCoding?) -> URL? {
        if let url = item as? URL {
            return url
        }
        if let data = item as? Data {
            return URL(dataRepresentation: data, relativeTo: nil)
        }
        if let string = item as? String {
            return URL(string: string)
        }
        return nil
    }
}

private struct PrepareWindowConfigurator: NSViewRepresentable {
    let minimumSize: NSSize
    let preferredSize: NSSize
    let resetToken: UUID

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            configureWindow(for: view, context: context)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            configureWindow(for: nsView, context: context)
        }
    }

    private func configureWindow(for view: NSView, context: Context) {
        guard let window = view.window else { return }

        window.setFrameAutosaveName("")
        window.minSize = minimumSize

        if context.coordinator.appliedResetToken != resetToken {
            window.setContentSize(preferredSize, animated: false)
            context.coordinator.appliedResetToken = resetToken
        }
    }

    final class Coordinator {
        var appliedResetToken: UUID?
    }
}

private extension NSWindow {
    func setContentSize(_ size: NSSize, animated: Bool) {
        guard animated else {
            setContentSize(size)
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.allowsImplicitAnimation = true
            setContentSize(size)
        }
    }
}
