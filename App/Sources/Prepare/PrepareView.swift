import AppKit
import AppUIKit
import DocumentCore
import SwiftUI
import UniformTypeIdentifiers

enum PrepareWindowChrome {
    /// Inset below traffic-light buttons when the prepare window uses a hidden title bar.
    static let contentTopInset: CGFloat = 0
    static let horizontalPadding: CGFloat = 0
    static let compactHeaderHeight: CGFloat = 60

    /// Matches `DocumentSanitizeContentView.Layout.windowWidth`.
    static let documentContentWidth: CGFloat = 782
    /// Matches `DirectoryCheckLayout.windowWidth`.
    static let directoryContentWidth: CGFloat = 640
    static let emptyContentWidth: CGFloat = documentContentWidth

    static func contentWidth(for selection: PrepareSelection?) -> CGFloat {
        switch selection {
        case .documents:
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
                case let .documents(fileURLs):
                    DocumentSanitizeContentView(fileURLs: fileURLs)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .id(fileURLs.map(\.path).joined(separator: "|"))
                case let .directory(directoryURL):
                    DirectoryCheckContentView(directoryURL: directoryURL)
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
        OffsendStrings.prepareDropHint
    }

    private func applyReplacement(from urls: [URL]) {
        guard !urls.isEmpty else { return }
        if let replacement = PrepareURLClassification.selection(forMultiple: urls) {
            selection = replacement
        } else {
            PrepareImportAlert.presentUnsupported(urls: urls)
        }
    }

    private func bootstrapFromWindowPathIfNeeded() {
        guard let prepareWindowPath else { return }
        let url = URL(fileURLWithPath: prepareWindowPath)
        if let resolved = PrepareURLClassification.selection(forWindowPath: prepareWindowPath) {
            guard selection != resolved else { return }
            selection = resolved
        } else if !PrepareURLClassification.isDirectory(url) {
            PrepareImportAlert.presentUnsupported(urls: [url])
        }
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
        panel.allowsMultipleSelection = true
        panel.prompt = OffsendStrings.prepareSelectPrompt

        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }
        applyReplacement(from: panel.urls)
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        let fileProviders = providers.filter {
            $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
        }
        guard !fileProviders.isEmpty else { return false }

        let group = DispatchGroup()
        let collector = DroppedFileURLCollector(count: fileProviders.count)

        for (index, provider) in fileProviders.enumerated() {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                collector.set(Self.fileURL(from: item), at: index)
                group.leave()
            }
        }

        group.notify(queue: .main) {
            let urls = collector.orderedURLs()
            guard !urls.isEmpty else { return }
            if let resolved = PrepareURLClassification.selection(forMultiple: urls) {
                self.selection = resolved
            } else {
                PrepareImportAlert.presentUnsupported(urls: urls)
            }
        }
        return true
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

/// `loadItem` callbacks arrive on arbitrary queues; guards index-ordered URL writes with a lock.
private final class DroppedFileURLCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var urls: [URL?]

    init(count: Int) {
        urls = Array(repeating: nil, count: count)
    }

    func set(_ url: URL?, at index: Int) {
        lock.lock()
        urls[index] = url
        lock.unlock()
    }

    func orderedURLs() -> [URL] {
        lock.lock()
        defer { lock.unlock() }
        return urls.compactMap { $0 }
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
