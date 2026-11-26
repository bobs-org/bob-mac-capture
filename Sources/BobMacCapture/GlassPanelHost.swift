import AppKit
import SwiftUI

/// Interaction is chosen by each HUD. Refs confirmations keep their
/// pointer-transparent behavior; the snooze HUD accepts clicks while
/// remaining a non-activating panel.
enum GlassPanelInteraction: Equatable {
    case passThrough
    case interactive
}

/// Placement choices shared by the Refs confirmations and wake HUD.
enum GlassPanelPlacement {
    case centered(on: NSRect)
    case aboveFooter(of: NSRect, footerHeight: CGFloat, outerPadding: CGFloat)
    case topCenter(in: NSRect, inset: CGFloat)
}

@MainActor
enum GlassPanelHost {
    static func configure(
        _ panel: NSPanel,
        interaction: GlassPanelInteraction,
        level: NSWindow.Level = .floating
    ) {
        panel.isFloatingPanel = true
        panel.level = level
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
        panel.ignoresMouseEvents = interaction == .passThrough
        panel.acceptsMouseMovedEvents = interaction == .interactive
    }

    static func frame(size: NSSize, placement: GlassPanelPlacement) -> NSRect {
        switch placement {
        case .centered(let host):
            return NSRect(
                x: host.midX - size.width / 2,
                y: host.midY - size.height / 2,
                width: size.width,
                height: size.height
            )
        case .aboveFooter(let host, let footerHeight, let outerPadding):
            let bottom = host.minY + outerPadding + footerHeight + 14
            return NSRect(
                x: host.midX - size.width / 2,
                y: bottom,
                width: size.width,
                height: size.height
            )
        case .topCenter(let visibleFrame, let inset):
            let width = min(size.width, max(1, visibleFrame.width - inset * 2))
            let height = min(size.height, max(1, visibleFrame.height - inset * 2))
            return NSRect(
                x: visibleFrame.midX - width / 2,
                y: visibleFrame.maxY - inset - height,
                width: width,
                height: height
            )
        }
    }

    static func visibleFrameAtPointer(
        pointer: NSPoint = NSEvent.mouseLocation,
        screens: [NSScreen] = NSScreen.screens,
        fallback: NSScreen? = NSScreen.main
    ) -> NSRect? {
        screens.first(where: { $0.frame.contains(pointer) })?.visibleFrame
            ?? fallback?.visibleFrame
    }

    static func install(
        content: NSView,
        size: NSSize,
        in panel: NSPanel,
        reduceTransparency: Bool,
        opaqueCornerRadius: CGFloat = 24,
        glassCornerRadius: CGFloat? = nil
    ) {
        content.frame = NSRect(origin: .zero, size: size)
        guard !reduceTransparency else {
            content.wantsLayer = true
            content.layer?.cornerRadius = opaqueCornerRadius
            content.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
            panel.contentView = content
            return
        }

        let glass = NSGlassEffectView()
        glass.cornerRadius = glassCornerRadius ?? size.height / 2
        glass.contentView = content
        glass.frame = NSRect(origin: .zero, size: size)
        panel.contentView = glass
    }
}
