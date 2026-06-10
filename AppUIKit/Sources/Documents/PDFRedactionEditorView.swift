import AppKit
import PDFKit
import SwiftUI

public enum PDFRedactionDocumentSource: Equatable {
    case file(URL)
    /// `id` uniquely identifies the in-memory payload so the editor can detect
    /// changes in O(1) instead of hashing the whole buffer on every update.
    case memory(Data, id: AnyHashable)
    /// Already-parsed document, so recreating the editor (e.g. on tab switch)
    /// does not re-parse the PDF. `id` identifies the payload like `memory`.
    case document(PDFDocument, id: AnyHashable)
}

/// A redaction rectangle expressed in PDF page coordinates, drawn as a live
/// overlay above the document so adding/removing regions never rebuilds the PDF.
public struct PDFRedactionOverlayBox: Equatable {
    public let pageIndex: Int
    public let bounds: CGRect

    public init(pageIndex: Int, bounds: CGRect) {
        self.pageIndex = pageIndex
        self.bounds = bounds
    }
}

public struct PDFRedactionEditorView: View {
    private let document: PDFRedactionDocumentSource
    private let regions: [PDFRedactionOverlayBox]
    private let canUndo: Bool
    private let canRedo: Bool
    private let isToolbarDisabled: Bool
    private let undoAccessibilityLabel: String
    private let redoAccessibilityLabel: String
    private let copyAccessibilityLabel: String?
    private let canCopy: Bool
    private let onUndo: () -> Void
    private let onRedo: () -> Void
    private let onCopy: (() -> Void)?
    private let onManualRegionAdded: (Int, CGRect) -> Void

    @State private var zoomPercentage = 100
    @State private var zoomAction: PDFZoomAction?

    public init(
        document: PDFRedactionDocumentSource,
        regions: [PDFRedactionOverlayBox] = [],
        canUndo: Bool,
        canRedo: Bool,
        isToolbarDisabled: Bool = false,
        undoAccessibilityLabel: String,
        redoAccessibilityLabel: String,
        copyAccessibilityLabel: String? = nil,
        canCopy: Bool = false,
        onUndo: @escaping () -> Void,
        onRedo: @escaping () -> Void,
        onCopy: (() -> Void)? = nil,
        onManualRegionAdded: @escaping (Int, CGRect) -> Void
    ) {
        self.document = document
        self.regions = regions
        self.canUndo = canUndo
        self.canRedo = canRedo
        self.isToolbarDisabled = isToolbarDisabled
        self.undoAccessibilityLabel = undoAccessibilityLabel
        self.redoAccessibilityLabel = redoAccessibilityLabel
        self.copyAccessibilityLabel = copyAccessibilityLabel
        self.canCopy = canCopy
        self.onUndo = onUndo
        self.onRedo = onRedo
        self.onCopy = onCopy
        self.onManualRegionAdded = onManualRegionAdded
    }

    public var body: some View {
        ZStack(alignment: .bottom) {
            PDFRedactionEditorRepresentable(
                document: document,
                regions: regions,
                isEditing: true,
                canUndo: canUndo,
                canRedo: canRedo,
                zoomAction: $zoomAction,
                zoomPercentage: $zoomPercentage,
                onUndo: onUndo,
                onRedo: onRedo,
                onManualRegionAdded: onManualRegionAdded
            )
            .background(Color.ofBg2)
            .clipShape(RoundedRectangle(cornerRadius: OFRadius.md))
            .overlay(
                RoundedRectangle(cornerRadius: OFRadius.md)
                    .stroke(Color.ofBorder, lineWidth: 1)
            )

            pdfBottomToolbar
                .padding(OFSpacing.sm)
        }
    }

    private var pdfBottomToolbar: some View {
        HStack(spacing: OFSpacing.sm) {
            HStack(spacing: 6) {
                toolbarIconButton(
                    icon: "arrow.uturn.backward",
                    accessibilityLabel: undoAccessibilityLabel,
                    isDisabled: isToolbarDisabled || !canUndo,
                    action: onUndo
                )

                toolbarIconButton(
                    icon: "arrow.uturn.forward",
                    accessibilityLabel: redoAccessibilityLabel,
                    isDisabled: isToolbarDisabled || !canRedo,
                    action: onRedo
                )

                if let copyAccessibilityLabel, let onCopy {
                    toolbarDivider

                    toolbarIconButton(
                        icon: "doc.on.doc",
                        accessibilityLabel: copyAccessibilityLabel,
                        isDisabled: isToolbarDisabled || !canCopy,
                        action: onCopy
                    )
                }
            }

            Spacer(minLength: OFSpacing.sm)

            HStack(spacing: 2) {
                toolbarIconButton(
                    icon: "minus",
                    accessibilityLabel: "Zoom out",
                    isDisabled: isToolbarDisabled,
                    action: { zoomAction = .zoomOut }
                )

                Text("\(zoomPercentage)%")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(.ofTextSub)
                    .frame(minWidth: 44)
                    .multilineTextAlignment(.center)

                toolbarIconButton(
                    icon: "plus",
                    accessibilityLabel: "Zoom in",
                    isDisabled: isToolbarDisabled,
                    action: { zoomAction = .zoomIn }
                )

                toolbarDivider

                toolbarIconButton(
                    icon: "arrow.up.left.and.arrow.down.right",
                    accessibilityLabel: "Fit to width",
                    isDisabled: isToolbarDisabled,
                    action: { zoomAction = .fitToWidth }
                )
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.ofBg0.opacity(0.94))
        .cornerRadius(OFRadius.sm)
        .overlay(
            RoundedRectangle(cornerRadius: OFRadius.sm)
                .stroke(Color.ofBorder, lineWidth: 1)
        )
    }

    private var toolbarDivider: some View {
        Rectangle()
            .fill(Color.ofBorder)
            .frame(width: 1, height: 16)
            .padding(.horizontal, 2)
    }

    private func toolbarIconButton(
        icon: String,
        accessibilityLabel: String,
        isDisabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(isDisabled ? .ofTextMuted.opacity(0.45) : .ofTextSub)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .accessibilityLabel(accessibilityLabel)
    }
}

enum PDFZoomAction: Equatable {
    case zoomIn
    case zoomOut
    case fitToWidth
}

// MARK: - Representable

private struct PDFRedactionEditorRepresentable: NSViewRepresentable {
    let document: PDFRedactionDocumentSource
    let regions: [PDFRedactionOverlayBox]
    let isEditing: Bool
    let canUndo: Bool
    let canRedo: Bool
    @Binding var zoomAction: PDFZoomAction?
    @Binding var zoomPercentage: Int
    let onUndo: () -> Void
    let onRedo: () -> Void
    let onManualRegionAdded: (Int, CGRect) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            zoomPercentage: $zoomPercentage,
            onUndo: onUndo,
            onRedo: onRedo,
            onManualRegionAdded: onManualRegionAdded
        )
    }

    func makeNSView(context: Context) -> PDFRedactionEditorContainerView {
        let view = PDFRedactionEditorContainerView()
        let coordinator = context.coordinator
        view.onManualRegionAdded = coordinator.handleManualRegionAdded
        view.onUndo = coordinator.handleUndo
        view.onRedo = coordinator.handleRedo
        view.onZoomPercentageChanged = coordinator.handleZoomPercentageChanged
        coordinator.lastDocumentFingerprint = PDFDocumentFingerprint(document)
        view.updatePDFDocument(source: document)
        view.redactionRegions = regions
        view.isEditing = isEditing
        view.keyboardCanUndo = canUndo
        view.keyboardCanRedo = canRedo
        return view
    }

    func updateNSView(_ nsView: PDFRedactionEditorContainerView, context: Context) {
        let coordinator = context.coordinator
        coordinator.onUndo = onUndo
        coordinator.onRedo = onRedo
        coordinator.onManualRegionAdded = onManualRegionAdded

        nsView.redactionRegions = regions

        if nsView.isEditing != isEditing {
            nsView.isEditing = isEditing
        }

        if nsView.keyboardCanUndo != canUndo {
            nsView.keyboardCanUndo = canUndo
        }
        if nsView.keyboardCanRedo != canRedo {
            nsView.keyboardCanRedo = canRedo
        }

        if let action = zoomAction {
            switch action {
            case .zoomIn:
                nsView.zoomIn()
            case .zoomOut:
                nsView.zoomOut()
            case .fitToWidth:
                nsView.fitToWidth()
            }
            DispatchQueue.main.async {
                zoomAction = nil
            }
        }

        let fingerprint = PDFDocumentFingerprint(document)
        guard coordinator.lastDocumentFingerprint != fingerprint else { return }
        coordinator.lastDocumentFingerprint = fingerprint
        nsView.updatePDFDocument(source: document)
    }

    static func dismantleNSView(_ nsView: PDFRedactionEditorContainerView, coordinator: Coordinator) {
        nsView.releasePDFResources()
        coordinator.lastDocumentFingerprint = nil
    }

    final class Coordinator {
        var onManualRegionAdded: (Int, CGRect) -> Void
        var onUndo: () -> Void
        var onRedo: () -> Void
        var lastDocumentFingerprint: PDFDocumentFingerprint?
        private var lastReportedZoomPercentage: Int?
        private let zoomPercentage: Binding<Int>

        init(
            zoomPercentage: Binding<Int>,
            onUndo: @escaping () -> Void,
            onRedo: @escaping () -> Void,
            onManualRegionAdded: @escaping (Int, CGRect) -> Void
        ) {
            self.zoomPercentage = zoomPercentage
            self.onUndo = onUndo
            self.onRedo = onRedo
            self.onManualRegionAdded = onManualRegionAdded
        }

        func handleManualRegionAdded(pageIndex: Int, bounds: CGRect) {
            performOnMain { self.onManualRegionAdded(pageIndex, bounds) }
        }

        func handleUndo() {
            performOnMain { self.onUndo() }
        }

        func handleRedo() {
            performOnMain { self.onRedo() }
        }

        func handleZoomPercentageChanged(_ percentage: Int) {
            guard lastReportedZoomPercentage != percentage else { return }
            lastReportedZoomPercentage = percentage
            performOnMain {
                if self.zoomPercentage.wrappedValue != percentage {
                    self.zoomPercentage.wrappedValue = percentage
                }
            }
        }
    }
}

// MARK: - PDF fingerprint

private enum PDFDocumentFingerprint: Equatable {
    case file(String)
    case memory(AnyHashable)
    case document(AnyHashable)

    init(_ source: PDFRedactionDocumentSource) {
        switch source {
        case let .file(url):
            self = .file(url.standardizedFileURL.path)
        case let .memory(_, id):
            self = .memory(id)
        case let .document(_, id):
            self = .document(id)
        }
    }
}

// MARK: - Container

private final class PDFRedactionEditorContainerView: NSView {
    private let pdfView = ZoomablePDFView()
    private let regionsOverlay = PDFRedactionRegionsOverlayView()
    private let dragOverlay = PDFRedactionDragOverlayView()

    private var fitScaleFactor: CGFloat = 1
    private var lastReportedZoomPercentage: Int?
    private static let zoomStep: CGFloat = 1.25
    private var magnifyEventMonitor: Any?
    private var keyEventMonitor: Any?
    private var eventMonitorsInstalled = false
    private var currentSource: PDFRedactionDocumentSource?
    private var scrollBoundsObserver: Any?

    var redactionRegions: [PDFRedactionOverlayBox] = [] {
        didSet {
            guard oldValue != redactionRegions else { return }
            regionsOverlay.regions = redactionRegions
        }
    }

    var isEditing = false {
        didSet {
            guard oldValue != isEditing else { return }
            dragOverlay.isHidden = !isEditing
            window?.invalidateCursorRects(for: dragOverlay)
        }
    }

    var onManualRegionAdded: ((Int, CGRect) -> Void)?
    var onUndo: (() -> Void)?
    var onRedo: (() -> Void)?
    var onZoomPercentageChanged: ((Int) -> Void)?
    var keyboardCanUndo = false
    var keyboardCanRedo = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true

        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.backgroundColor = NSColor(Color.ofBg2)
        pdfView.onScaleChanged = { [weak self] in
            self?.reportZoomPercentage()
            self?.regionsOverlay.needsDisplay = true
        }

        regionsOverlay.pdfView = pdfView
        dragOverlay.pdfView = pdfView

        dragOverlay.onRegionCompleted = { [weak self] viewRect in
            self?.handleCompletedDrag(viewRect: viewRect)
        }
        dragOverlay.isHidden = true

        addSubview(pdfView)
        addSubview(regionsOverlay)
        addSubview(dragOverlay)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        removeEventMonitors()
        removeScrollObserver()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            installEventMonitorsIfNeeded()
            if pdfView.document == nil, let currentSource {
                updatePDFDocument(source: currentSource)
            }
        } else {
            // The window is gone (e.g. closed). Release the PDF document eagerly
            // so its backing bytes are freed immediately instead of waiting for
            // SwiftUI to call `dismantleNSView`, which can be delayed or skipped
            // for `WindowGroup` scenes.
            removeEventMonitors()
            releasePDFDocument()
        }
    }

    override func layout() {
        super.layout()
        pdfView.frame = bounds
        regionsOverlay.frame = bounds
        dragOverlay.frame = bounds

        guard bounds.width > 1, bounds.height > 1, pdfView.document != nil else { return }

        installScrollObserverIfNeeded()
        regionsOverlay.needsDisplay = true

        if pdfView.autoScales {
            captureFitScale()
        }
        reportZoomPercentage()
    }

    /// Repaint the redaction overlay whenever the PDF scrolls so the page-anchored
    /// boxes follow the content without rebuilding the document.
    private func installScrollObserverIfNeeded() {
        guard scrollBoundsObserver == nil,
              let scrollView = Self.enclosedScrollView(of: pdfView) else { return }

        let clipView = scrollView.contentView
        clipView.postsBoundsChangedNotifications = true
        scrollBoundsObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: clipView,
            queue: .main
        ) { [weak self] _ in
            self?.regionsOverlay.needsDisplay = true
        }
    }

    private func removeScrollObserver() {
        if let scrollBoundsObserver {
            NotificationCenter.default.removeObserver(scrollBoundsObserver)
            self.scrollBoundsObserver = nil
        }
    }

    private static func enclosedScrollView(of view: NSView) -> NSScrollView? {
        if let scrollView = view as? NSScrollView { return scrollView }
        for subview in view.subviews {
            if let scrollView = enclosedScrollView(of: subview) { return scrollView }
        }
        return nil
    }

    func zoomIn() {
        setManualScale(pdfView.scaleFactor * Self.zoomStep)
    }

    func zoomOut() {
        setManualScale(pdfView.scaleFactor / Self.zoomStep)
    }

    func fitToWidth() {
        pdfView.autoScales = true
        captureFitScale()
        reportZoomPercentage()
    }

    private func installEventMonitorsIfNeeded() {
        guard !eventMonitorsInstalled else { return }
        eventMonitorsInstalled = true

        magnifyEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .magnify) { [weak self] event in
            guard let self,
                  let window = self.window,
                  event.window == window else {
                return event
            }

            let location = self.convert(event.locationInWindow, from: nil)
            guard self.bounds.contains(location) else { return event }

            self.setManualScale(self.pdfView.scaleFactor * (1 + event.magnification))
            return nil
        }

        keyEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self,
                  let window = self.window,
                  event.window == window,
                  self.shouldHandleKeyboardShortcut(in: window, event: event) else {
                return event
            }

            guard event.modifierFlags.contains(.command) else { return event }

            if event.charactersIgnoringModifiers == "z" {
                if event.modifierFlags.contains(.shift) {
                    guard self.keyboardCanRedo else { return event }
                    self.onRedo?()
                } else {
                    guard self.keyboardCanUndo else { return event }
                    self.onUndo?()
                }
                return nil
            }

            return event
        }
    }

    private func removeEventMonitors() {
        guard eventMonitorsInstalled else { return }
        eventMonitorsInstalled = false

        if let magnifyEventMonitor {
            NSEvent.removeMonitor(magnifyEventMonitor)
            self.magnifyEventMonitor = nil
        }
        if let keyEventMonitor {
            NSEvent.removeMonitor(keyEventMonitor)
            self.keyEventMonitor = nil
        }
    }

    private func shouldHandleKeyboardShortcut(in window: NSWindow, event: NSEvent) -> Bool {
        let pointer = convert(event.locationInWindow, from: nil)
        if bounds.contains(pointer) { return true }
        guard let responder = window.firstResponder as? NSView else { return false }
        return containsViewInSubtree(responder)
    }

    private func containsViewInSubtree(_ view: NSView) -> Bool {
        var current: NSView? = view
        while let node = current {
            if node === self { return true }
            current = node.superview
        }
        return false
    }

    func releasePDFResources() {
        removeEventMonitors()
        onManualRegionAdded = nil
        onUndo = nil
        onRedo = nil
        onZoomPercentageChanged = nil
        currentSource = nil
        releasePDFDocument()
    }

    private func releasePDFDocument() {
        removeScrollObserver()
        regionsOverlay.needsDisplay = true
        guard pdfView.document != nil else { return }
        autoreleasepool {
            pdfView.document = nil
        }
    }

    func updatePDFDocument(source: PDFRedactionDocumentSource) {
        currentSource = source
        let savedViewState = viewState()

        let document: PDFDocument?
        switch source {
        case let .file(url):
            document = PDFDocument(url: url)
        case let .memory(data, _):
            document = PDFDocument(data: data)
        case let .document(parsedDocument, _):
            document = parsedDocument
        }
        guard let document else { return }
        pdfView.document = document

        if let savedViewState {
            restoreViewState(savedViewState, in: document)
        } else {
            pdfView.autoScales = true
            captureFitScale()
            reportZoomPercentage()
        }
    }

    private func setManualScale(_ scale: CGFloat) {
        pdfView.autoScales = false
        pdfView.scaleFactor = min(max(scale, pdfView.minScaleFactor), pdfView.maxScaleFactor)
        reportZoomPercentage()
    }

    private func captureFitScale() {
        fitScaleFactor = max(pdfView.scaleFactor, 0.01)
    }

    private func reportZoomPercentage() {
        if pdfView.autoScales {
            captureFitScale()
        }
        let percentage = Int(round(pdfView.scaleFactor / fitScaleFactor * 100))
        guard lastReportedZoomPercentage != percentage else { return }
        lastReportedZoomPercentage = percentage
        onZoomPercentageChanged?(percentage)
    }

    private struct ViewState {
        let pageIndex: Int
        let point: CGPoint
        let scaleFactor: CGFloat
        let autoScales: Bool
    }

    private func viewState() -> ViewState? {
        guard let document = pdfView.document,
              let page = pdfView.currentPage else {
            return nil
        }
        let pageIndex = document.index(for: page)
        let point = pdfView.currentDestination?.point ?? .zero
        return ViewState(
            pageIndex: pageIndex,
            point: point,
            scaleFactor: pdfView.scaleFactor,
            autoScales: pdfView.autoScales
        )
    }

    private func restoreViewState(_ state: ViewState, in document: PDFDocument) {
        pdfView.autoScales = state.autoScales
        if !state.autoScales {
            pdfView.scaleFactor = min(
                max(state.scaleFactor, pdfView.minScaleFactor),
                pdfView.maxScaleFactor
            )
        } else {
            captureFitScale()
        }

        guard state.pageIndex >= 0,
              state.pageIndex < document.pageCount,
              let page = document.page(at: state.pageIndex) else {
            reportZoomPercentage()
            return
        }
        pdfView.go(to: PDFDestination(page: page, at: state.point))
        reportZoomPercentage()
    }

    private func handleCompletedDrag(viewRect: NSRect) {
        guard let page = pdfView.page(
            for: NSPoint(x: viewRect.midX, y: viewRect.midY),
            nearest: true
        ),
            let document = pdfView.document else {
            return
        }

        let pageIndex = document.index(for: page)

        let topLeft = pdfView.convert(NSPoint(x: viewRect.minX, y: viewRect.maxY), to: page)
        let bottomRight = pdfView.convert(NSPoint(x: viewRect.maxX, y: viewRect.minY), to: page)
        var bounds = CGRect(
            x: min(topLeft.x, bottomRight.x),
            y: min(topLeft.y, bottomRight.y),
            width: abs(bottomRight.x - topLeft.x),
            height: abs(bottomRight.y - topLeft.y)
        )
        let pageBounds = page.bounds(for: pdfView.displayBox)
        bounds = bounds.intersection(pageBounds)

        guard !bounds.isNull, bounds.width > 4, bounds.height > 4 else { return }
        onManualRegionAdded?(pageIndex, bounds)
    }
}

// MARK: - PDF view

private final class ZoomablePDFView: PDFView {
    var onScaleChanged: (() -> Void)?

    override func scrollWheel(with event: NSEvent) {
        if event.modifierFlags.contains(.command) {
            autoScales = false
            let zoomFactor = 1 + event.deltaY * 0.01
            let newScale = scaleFactor * zoomFactor
            scaleFactor = min(max(newScale, minScaleFactor), maxScaleFactor)
            onScaleChanged?()
            return
        }

        super.scrollWheel(with: event)
    }
}

// MARK: - Redaction regions overlay

/// Draws committed redaction rectangles (in PDF page coordinates) as solid boxes
/// on top of the document. This lets the editor reflect added/removed regions
/// instantly without re-rendering or swapping the underlying `PDFDocument`.
private final class PDFRedactionRegionsOverlayView: NSView {
    weak var pdfView: PDFView?

    var regions: [PDFRedactionOverlayBox] = [] {
        didSet {
            guard oldValue != regions else { return }
            needsDisplay = true
        }
    }

    override var isOpaque: Bool { false }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard !regions.isEmpty,
              let pdfView,
              let document = pdfView.document else {
            return
        }

        NSColor.black.setFill()

        for region in regions {
            guard region.pageIndex >= 0,
                  region.pageIndex < document.pageCount,
                  let page = document.page(at: region.pageIndex) else {
                continue
            }

            let rectInPDFView = pdfView.convert(region.bounds, from: page)
            let rectInOverlay = convert(rectInPDFView, from: pdfView)
            guard rectInOverlay.intersects(bounds) else { continue }
            rectInOverlay.fill()
        }
    }
}

// MARK: - Drag overlay

private final class PDFRedactionDragOverlayView: NSView {
    weak var pdfView: PDFView?
    var onRegionCompleted: ((NSRect) -> Void)?

    private var dragStart: NSPoint?
    private var dragCurrent: NSPoint?
    private var dragPage: PDFPage?
    private var lastDirtyRect: NSRect = .zero

    override var isHidden: Bool {
        didSet {
            guard oldValue != isHidden else { return }
            window?.invalidateCursorRects(for: self)
        }
    }

    override var isOpaque: Bool { false }

    override func hitTest(_ point: NSPoint) -> NSView? {
        isHidden ? nil : self
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        guard !isHidden else { return }
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func mouseDown(with event: NSEvent) {
        NSCursor.crosshair.set()
        let point = convert(event.locationInWindow, from: nil)
        guard let page = page(at: point) else { return }
        dragPage = page
        dragStart = point
        dragCurrent = point
        setNeedsDisplaySelection()
    }

    override func mouseDragged(with event: NSEvent) {
        NSCursor.crosshair.set()
        dragCurrent = convert(event.locationInWindow, from: nil)
        setNeedsDisplaySelection()
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            invalidateSelectionDisplay()
            dragStart = nil
            dragCurrent = nil
            dragPage = nil
            window?.invalidateCursorRects(for: self)
        }

        guard let start = dragStart, let page = dragPage else { return }
        let end = convert(event.locationInWindow, from: nil)
        guard let rect = clampedSelectionRect(from: start, to: end, on: page),
              rect.width > 4, rect.height > 4 else { return }
        onRegionCompleted?(rect)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let start = dragStart,
              let current = dragCurrent,
              let page = dragPage,
              let rect = clampedSelectionRect(from: start, to: current, on: page) else { return }

        NSColor.black.withAlphaComponent(0.25).setFill()
        rect.fill()

        NSColor.controlAccentColor.setStroke()
        let path = NSBezierPath(rect: rect)
        path.lineWidth = 1.5
        path.stroke()
    }

    private func selectionRect(from start: NSPoint, to end: NSPoint) -> NSRect {
        NSRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        )
    }

    private func page(at point: NSPoint) -> PDFPage? {
        guard let pdfView else { return nil }
        let pointInPDFView = convert(point, to: pdfView)
        return pdfView.page(for: pointInPDFView, nearest: false)
    }

    private func pageBoundsInOverlay(for page: PDFPage) -> NSRect? {
        guard let pdfView else { return nil }
        let boundsInPDFView = pdfView.convert(page.bounds(for: pdfView.displayBox), from: page)
        return convert(boundsInPDFView, from: pdfView)
    }

    private func clampedSelectionRect(from start: NSPoint, to end: NSPoint, on page: PDFPage) -> NSRect? {
        guard let pageBounds = pageBoundsInOverlay(for: page) else { return nil }
        let raw = selectionRect(from: start, to: end)
        let clamped = raw.intersection(pageBounds)
        guard !clamped.isNull, clamped.width > 0, clamped.height > 0 else { return nil }
        return clamped
    }

    private func setNeedsDisplaySelection() {
        let newRect = paddedDirtyRect(for: dragStart, and: dragCurrent, on: dragPage)
        setNeedsDisplay(lastDirtyRect.union(newRect))
        lastDirtyRect = newRect
    }

    private func invalidateSelectionDisplay() {
        setNeedsDisplay(lastDirtyRect)
        lastDirtyRect = .zero
    }

    private func paddedDirtyRect(for start: NSPoint?, and end: NSPoint?, on page: PDFPage?) -> NSRect {
        guard let start, let end, let page,
              let rect = clampedSelectionRect(from: start, to: end, on: page) else { return .zero }
        return rect.insetBy(dx: -2, dy: -2)
    }
}

// MARK: - Main-thread dispatch

private func performOnMain(_ work: @escaping () -> Void) {
    if Thread.isMainThread {
        work()
    } else {
        DispatchQueue.main.async(execute: work)
    }
}
