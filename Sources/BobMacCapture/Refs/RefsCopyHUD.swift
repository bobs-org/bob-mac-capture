import AppKit
import RefsCore
import SwiftUI

enum RefsGlassToastStyle: Equatable {
    case copy
    case linked
    case moved
    case already
    case guarded
    case closedTab
    case warning

    var symbolName: String {
        switch self {
        case .copy: "checkmark.circle.fill"
        case .linked, .moved, .already: "timer"
        case .guarded: "lock.fill"
        case .closedTab: "xmark.square.fill"
        case .warning: "exclamationmark.triangle.fill"
        }
    }

    var color: Color {
        switch self {
        case .copy: .green
        case .linked, .moved: .pink
        case .already: .pink.opacity(0.6)
        case .guarded: .orange
        case .closedTab: .secondary
        case .warning: .orange
        }
    }

    static func today(_ style: RefsTodayLinkToast.Style) -> Self {
        switch style {
        case .linked: .linked
        case .moved: .moved
        case .already: .already
        case .guarded: .guarded
        }
    }
}

/// Borderless HUD panel: it never takes key or main, ignores the
/// mouse, and floats with the Refs collection behaviour.
final class RefsGlassToastPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Reusable glass toast for copy, Today-link, and tab-close confirmations.
/// Copy and last-tab toasts are centered over the panel's former frame;
/// Today-link and ordinary close toasts sit above the visible footer.
@MainActor
public final class RefsGlassToastController {
    public static let fadeInDuration: TimeInterval = 0.1
    public static let todayFadeInDuration: TimeInterval = 0.12
    public static let copyHoldDuration: TimeInterval = 1.0
    public static let fadeOutDuration: TimeInterval = 0.3

    private var panel: RefsGlassToastPanel?
    private var hostingView: NSHostingView<RefsGlassToastView>?
    private var fadeTask: Task<Void, Never>?
    private var showGeneration: UInt64 = 0
    private let reduceMotion: () -> Bool

    public init(
        reduceMotion: @escaping () -> Bool = {
            NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        }
    ) {
        self.reduceMotion = reduceMotion
    }

    /// Places a centered copy toast at the center of `host`.
    public static func frame(centeredOn host: NSRect, size: NSSize) -> NSRect {
        NSRect(
            x: host.midX - size.width / 2,
            y: host.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    /// The toast's bottom edge sits 14 pt above the panel footer.
    public static func frame(aboveFooterOf host: NSRect, size: NSSize) -> NSRect {
        let bottom = host.minY + RefsVisualTokens.outerPadding
            + RefsVisualTokens.footerHeight + 14
        return NSRect(
            x: host.midX - size.width / 2,
            y: bottom,
            width: size.width,
            height: size.height
        )
    }

    /// The panel configuration, static so geometry tests assert it
    /// without showing anything.
    public static func makePanel() -> NSPanel {
        makeToastPanel()
    }

    static func makeToastPanel() -> RefsGlassToastPanel {
        let panel = RefsGlassToastPanel(
            contentRect: NSRect(x: 0, y: 0, width: 240, height: 48),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .transient,
            .ignoresCycle,
        ]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = false
        panel.ignoresMouseEvents = true
        return panel
    }

    public func show(title: String, value: String, centeredOn host: NSRect) {
        present(
            title: title,
            value: value,
            detail: nil,
            style: .copy,
            holdDuration: Self.copyHoldDuration,
            fadeIn: Self.fadeInDuration,
            rises: false,
            frame: { Self.frame(centeredOn: host, size: $0) }
        )
    }

    public func show(
        title: String,
        value: String,
        detail: String,
        style: RefsTodayLinkToast.Style,
        holdDuration: TimeInterval,
        aboveFooterOf host: NSRect
    ) {
        present(
            title: title,
            value: value,
            detail: detail,
            style: .today(style),
            holdDuration: holdDuration,
            fadeIn: Self.todayFadeInDuration,
            rises: true,
            frame: { Self.frame(aboveFooterOf: host, size: $0) }
        )
    }

    public func show(
        title: String,
        value: String,
        detail: String?,
        centeredOn host: NSRect
    ) {
        present(
            title: title,
            value: value,
            detail: detail,
            style: .closedTab,
            holdDuration: RefsTabClosePresentation.toastHoldDuration,
            fadeIn: Self.todayFadeInDuration,
            rises: false,
            frame: { Self.frame(centeredOn: host, size: $0) }
        )
    }

    public func show(
        title: String,
        value: String,
        detail: String,
        style: RefsGlassToastStyle,
        centeredOn host: NSRect
    ) {
        present(
            title: title,
            value: value,
            detail: detail,
            style: style,
            holdDuration: 2.2,
            fadeIn: Self.todayFadeInDuration,
            rises: false,
            frame: { Self.frame(centeredOn: host, size: $0) }
        )
    }

    public func show(
        title: String,
        value: String,
        detail: String?,
        holdDuration: TimeInterval,
        aboveFooterOf host: NSRect
    ) {
        present(
            title: title,
            value: value,
            detail: detail,
            style: .closedTab,
            holdDuration: holdDuration,
            fadeIn: Self.todayFadeInDuration,
            rises: true,
            frame: { Self.frame(aboveFooterOf: host, size: $0) }
        )
    }

    public func dismiss() {
        fadeTask?.cancel()
        fadeTask = nil
        showGeneration += 1
        panel?.alphaValue = 0
        panel?.orderOut(nil)
    }

    private func present(
        title: String,
        value: String,
        detail: String?,
        style: RefsGlassToastStyle,
        holdDuration: TimeInterval,
        fadeIn: TimeInterval,
        rises: Bool,
        frame: (NSSize) -> NSRect
    ) {
        fadeTask?.cancel()
        showGeneration += 1
        let generation = showGeneration
        let panel = makePanelIfNeeded()
        let view = RefsGlassToastView(title: title, value: value, detail: detail, style: style)
        if let hostingView {
            hostingView.rootView = view
        } else {
            let hosting = NSHostingView(rootView: view)
            hosting.sizingOptions = [.intrinsicContentSize]
            hostingView = hosting
        }
        guard let hostingView else { return }
        hostingView.layoutSubtreeIfNeeded()
        var size = hostingView.fittingSize
        if size.width < 1 || size.height < 1 {
            size = NSSize(width: 240, height: 48)
        }
        installContent(hostingView, size: size, in: panel)
        let targetFrame = frame(size)
        let animateRise = rises && !reduceMotion()
        let startFrame = animateRise
            ? targetFrame.offsetBy(dx: 0, dy: -6) : targetFrame
        panel.setFrame(startFrame, display: true)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = fadeIn
            panel.animator().alphaValue = 1
            if animateRise {
                panel.animator().setFrame(targetFrame, display: true)
            }
        }
        fadeTask = Task { [weak self] in
            let hold = UInt64((fadeIn + holdDuration) * 1_000_000_000)
            try? await Task.sleep(nanoseconds: hold)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self, let panel = self.panel else { return }
                NSAnimationContext.runAnimationGroup(
                    { context in
                        context.duration = Self.fadeOutDuration
                        panel.animator().alphaValue = 0
                    },
                    completionHandler: { [weak self] in
                        Task { @MainActor in
                            guard let self, self.showGeneration == generation else { return }
                            panel.orderOut(nil)
                        }
                    }
                )
            }
        }
    }

    private func makePanelIfNeeded() -> RefsGlassToastPanel {
        if let panel { return panel }
        let created = Self.makeToastPanel()
        panel = created
        return created
    }

    private func installContent(
        _ hostingView: NSHostingView<RefsGlassToastView>,
        size: NSSize,
        in panel: RefsGlassToastPanel
    ) {
        hostingView.frame = NSRect(origin: .zero, size: size)
        if NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency {
            hostingView.wantsLayer = true
            hostingView.layer?.cornerRadius = 24
            hostingView.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
            panel.contentView = hostingView
            return
        }
        let glass = NSGlassEffectView()
        glass.cornerRadius = size.height / 2
        glass.contentView = hostingView
        glass.frame = NSRect(origin: .zero, size: size)
        panel.contentView = glass
    }
}

/// Compatibility name for copy-HUD geometry tests and call sites that
/// still describe the original one-line toast.
public typealias RefsCopyHUDController = RefsGlassToastController

/// Shared glass content. Copy keeps its compact checkmark treatment;
/// Today adds a pink or orange badge, reference title, and detail line.
/// Closed-tab toasts use `xmark.square.fill` in secondary tint and omit
/// the detail line when it is nil or empty.
@available(macOS 26.0, *)
struct RefsGlassToastView: View {
    let title: String
    let value: String
    var detail: String?
    var style: RefsGlassToastStyle = .copy
    var previewMode = false
    var reduceTransparency = false

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: style.symbolName)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(style.color)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(value)
                    .font(.system(size: 11.5, design: style == .copy ? .monospaced : .default))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: RefsVisualTokens.copyHUDMaxValueWidth, alignment: .leading)
                if let detail, !detail.isEmpty {
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background {
            if previewMode {
                Capsule().fill(
                    reduceTransparency
                        ? Color(nsColor: .windowBackgroundColor)
                        : Color.primary.opacity(0.08)
                )
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel([title, value, detail].compactMap { $0 }.joined(separator: ", "))
    }
}

/// The original copy fixture API remains a thin wrapper around the
/// shared toast content.
@available(macOS 26.0, *)
struct RefsCopyHUDView: View {
    let title: String
    let value: String
    var previewMode = false
    var reduceTransparency = false

    var body: some View {
        RefsGlassToastView(
            title: title,
            value: value,
            style: .copy,
            previewMode: previewMode,
            reduceTransparency: reduceTransparency
        )
    }
}
