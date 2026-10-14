import AppKit
import SwiftUI

/// Borderless HUD panel: it never takes key or main, ignores the
/// mouse, and floats with the Refs collection behaviour.
final class RefsCopyHUDPanel: NSPanel {
    override var canBecomeKey: Bool {
        false
    }

    override var canBecomeMain: Bool {
        false
    }
}

/// The glass copy HUD: a checkmark plus title over the copied value,
/// centred on Refs' former frame. Showing or re-presenting Refs calls
/// `dismiss()`.
@MainActor
public final class RefsCopyHUDController {
    public static let fadeInDuration: TimeInterval = 0.1
    public static let holdDuration: TimeInterval = 1.0
    public static let fadeOutDuration: TimeInterval = 0.3

    private var panel: RefsCopyHUDPanel?
    private var hostingView: NSHostingView<RefsCopyHUDView>?
    private var fadeTask: Task<Void, Never>?
    private var showGeneration: UInt64 = 0

    public init() {}

    /// Places a HUD of `size` at the centre of `host`.
    public static func frame(centeredOn host: NSRect, size: NSSize) -> NSRect {
        NSRect(
            x: host.midX - size.width / 2,
            y: host.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    /// The panel configuration, static so geometry tests assert it
    /// without showing anything.
    public static func makePanel() -> NSPanel {
        makeHUDPanel()
    }

    static func makeHUDPanel() -> RefsCopyHUDPanel {
        let panel = RefsCopyHUDPanel(
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
        fadeTask?.cancel()
        showGeneration += 1
        let generation = showGeneration
        let panel = makePanelIfNeeded()
        let view = RefsCopyHUDView(title: title, value: value)
        if let hostingView {
            hostingView.rootView = view
        } else {
            let hosting = NSHostingView(rootView: view)
            hosting.sizingOptions = [.intrinsicContentSize]
            hostingView = hosting
        }
        guard let hostingView else {
            return
        }
        hostingView.layoutSubtreeIfNeeded()
        var size = hostingView.fittingSize
        if size.width < 1 || size.height < 1 {
            size = NSSize(width: 240, height: 48)
        }
        installContent(hostingView, size: size, in: panel)
        panel.setFrame(Self.frame(centeredOn: host, size: size), display: true)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.fadeInDuration
            panel.animator().alphaValue = 1
        }
        fadeTask = Task { [weak self] in
            let hold = UInt64(
                (Self.fadeInDuration + Self.holdDuration) * 1_000_000_000
            )
            try? await Task.sleep(nanoseconds: hold)
            guard !Task.isCancelled else {
                return
            }
            await MainActor.run {
                guard let self, let panel = self.panel else {
                    return
                }
                NSAnimationContext.runAnimationGroup(
                    { context in
                        context.duration = Self.fadeOutDuration
                        panel.animator().alphaValue = 0
                    },
                    completionHandler: { [weak self] in
                        Task { @MainActor in
                            guard let self,
                                self.showGeneration == generation
                            else {
                                return
                            }
                            panel.orderOut(nil)
                        }
                    }
                )
            }
        }
    }

    public func dismiss() {
        fadeTask?.cancel()
        fadeTask = nil
        showGeneration += 1
        panel?.alphaValue = 0
        panel?.orderOut(nil)
    }

    private func makePanelIfNeeded() -> RefsCopyHUDPanel {
        if let panel {
            return panel
        }
        let created = Self.makeHUDPanel()
        panel = created
        return created
    }

    private func installContent(
        _ hostingView: NSHostingView<RefsCopyHUDView>,
        size: NSSize,
        in panel: RefsCopyHUDPanel
    ) {
        hostingView.frame = NSRect(origin: .zero, size: size)
        if NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency {
            hostingView.wantsLayer = true
            hostingView.layer?.cornerRadius = size.height / 2
            hostingView.layer?.backgroundColor =
                NSColor.windowBackgroundColor.cgColor
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

/// HUD content: a green check beside the confirmation title over the
/// copied value, middle-truncated at 380 pt. The live glass capsule
/// comes from `NSGlassEffectView`; `previewMode` paints a stand-in
/// capsule for design fixtures.
@available(macOS 26.0, *)
struct RefsCopyHUDView: View {
    let title: String
    let value: String
    var previewMode = false
    var reduceTransparency = false

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 18))
                .foregroundStyle(.green)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(value)
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(
                        maxWidth: RefsVisualTokens.copyHUDMaxValueWidth,
                        alignment: .leading
                    )
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background {
            if previewMode {
                Capsule()
                    .fill(
                        reduceTransparency
                            ? Color(nsColor: .windowBackgroundColor)
                            : Color.primary.opacity(0.08)
                    )
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(value)")
    }
}
