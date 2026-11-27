import AppKit

/// The menu-bar mark for Bob Mac Capture: a geometric lowercase "b" (a vertical
/// stem plus a circular bowl, both one stroke weight) with a solid bullet
/// centered in the bowl.
///
/// The mark reads as "b" for Bob at a glance, and the bowl-plus-bullet doubles
/// as a target: the bullet is the captured thought, since every capture becomes
/// a bullet in the vault. It is drawn in code as a monochrome template image,
/// so AppKit tints it for light and dark menu bars, Liquid Glass wallpapers,
/// and the highlighted (menu-open) state, and it stays crisp at 1x, 2x, and 3x
/// with no bundled assets. (SwiftPM resources would break the hand-assembled,
/// codesigned `.app`; `Scripts/bundle.sh` copies only the executable and
/// `Info.plist`, so drawing in code is the reliability choice.)
enum StatusItemGlyph {
    /// Which glyph variant to draw.
    enum State: Equatable {
        /// The resting bullet-b, shown while `bob` resolves.
        case ready
        /// The stem and bowl are unchanged; the bullet becomes a "!".
        case bobUnresolved
    }

    /// Every number from the design table, in a y-down 18x18pt canvas.
    enum Metrics {
        /// Canvas edge length in points.
        static let canvasLength: CGFloat = 18
        /// Shared stroke weight, matching the menu bar's SF Symbol weight.
        static let strokeWidth: CGFloat = 1.5
        /// Stem endpoints. Ink top is y = 2.5 via the round cap.
        static let stemTop = CGPoint(x: 4.25, y: 3.25)
        static let stemBottom = CGPoint(x: 4.25, y: 10.0)
        /// Bowl center and centerline radius (outer 5.5, counter 4.0).
        static let bowlCenter = CGPoint(x: 9.0, y: 10.0)
        static let bowlRadius: CGFloat = 4.75
        /// Resting bullet radius.
        static let bulletRadius: CGFloat = 1.6
        /// Alert bar endpoints and width (ink y 7.0-10.5 via the round caps).
        static let alertBarTop = CGPoint(x: 9.0, y: 7.7)
        static let alertBarBottom = CGPoint(x: 9.0, y: 9.8)
        static let alertBarWidth: CGFloat = 1.4
        /// Alert dot center and radius.
        static let alertDotCenter = CGPoint(x: 9.0, y: 12.2)
        static let alertDotRadius: CGFloat = 0.8
        /// Inner radius of the stroked bowl.
        static let counterRadius: CGFloat = 4.0
        /// Wake-beacon accessory: a small amber badge in the top-right corner.
        static let beaconCenter = CGPoint(x: 14.2, y: 4.2)
        static let beaconRadius: CGFloat = 3.3
        static let beaconFontSize: CGFloat = 6.5
        /// Union of all ink in either state.
        static let inkBounds = NSRect(x: 3.5, y: 2.5, width: 11, height: 13)
    }

    /// Draws the glyph for `state`, tinted by AppKit as a template image.
    /// `bulletRadius` varies only during the capture-landed pulse. The wake
    /// beacon is drawn separately so this base remains template-tinted.
    static func image(
        for state: State,
        bulletRadius: CGFloat = Metrics.bulletRadius
    ) -> NSImage {
        let length = Metrics.canvasLength
        let size = NSSize(width: length, height: length)
        let image = NSImage(size: size, flipped: true) { _ in
            NSColor.black.setFill()
            NSColor.black.setStroke()

            let stem = NSBezierPath()
            stem.move(to: Metrics.stemTop)
            stem.line(to: Metrics.stemBottom)
            stem.lineWidth = Metrics.strokeWidth
            stem.lineCapStyle = .round
            stem.stroke()

            let bowlSide = Metrics.bowlRadius * 2
            let bowlRect = NSRect(
                x: Metrics.bowlCenter.x - Metrics.bowlRadius,
                y: Metrics.bowlCenter.y - Metrics.bowlRadius,
                width: bowlSide,
                height: bowlSide
            )
            let bowl = NSBezierPath(ovalIn: bowlRect)
            bowl.lineWidth = Metrics.strokeWidth
            bowl.stroke()

            switch state {
            case .ready:
                let bulletSide = bulletRadius * 2
                let bulletRect = NSRect(
                    x: Metrics.bowlCenter.x - bulletRadius,
                    y: Metrics.bowlCenter.y - bulletRadius,
                    width: bulletSide,
                    height: bulletSide
                )
                NSBezierPath(ovalIn: bulletRect).fill()
            case .bobUnresolved:
                let bar = NSBezierPath()
                bar.move(to: Metrics.alertBarTop)
                bar.line(to: Metrics.alertBarBottom)
                bar.lineWidth = Metrics.alertBarWidth
                bar.lineCapStyle = .round
                bar.stroke()

                let dotSide = Metrics.alertDotRadius * 2
                let dotRect = NSRect(
                    x: Metrics.alertDotCenter.x - Metrics.alertDotRadius,
                    y: Metrics.alertDotCenter.y - Metrics.alertDotRadius,
                    width: dotSide,
                    height: dotSide
                )
                NSBezierPath(ovalIn: dotRect).fill()
            }

            return true
        }
        image.isTemplate = true
        let label = StatusItemPresentation(isBobResolved: state == .ready)
        image.accessibilityDescription = label.accessibilityLabel
        return image
    }
}

/// The amber wake badge is a separate non-template image layered over the
/// menu-bar button's template glyph, so AppKit can tint the base independently.
enum StatusItemBeaconGlyph {
    static func image(count: Int) -> NSImage {
        let size = NSSize(
            width: StatusItemGlyph.Metrics.canvasLength,
            height: StatusItemGlyph.Metrics.canvasLength
        )
        let image = NSImage(size: size, flipped: true) { _ in
            guard count > 0 else { return true }
            NSColor.systemOrange.setFill()
            let radius = StatusItemGlyph.Metrics.beaconRadius
            let center = StatusItemGlyph.Metrics.beaconCenter
            let bells = [-1.0, 1.0].map { offset in
                NSRect(x: center.x + offset * 1.55 - 0.7, y: 0.55, width: 1.4, height: 1.5)
            }
            for bell in bells {
                NSBezierPath(ovalIn: bell).fill()
            }
            NSColor.systemOrange.setStroke()
            let feet = NSBezierPath()
            feet.move(to: NSPoint(x: center.x - 1.45, y: 6.55))
            feet.line(to: NSPoint(x: center.x - 2.05, y: 7.9))
            feet.move(to: NSPoint(x: center.x + 1.45, y: 6.55))
            feet.line(to: NSPoint(x: center.x + 2.05, y: 7.9))
            feet.lineWidth = 0.9
            feet.lineCapStyle = .round
            feet.stroke()
            NSBezierPath(
                ovalIn: NSRect(
                    x: center.x - radius,
                    y: center.y - radius,
                    width: radius * 2,
                    height: radius * 2
                )
            ).fill()

            let label = count > 99 ? "99+" : "\(count)"
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            let text = NSAttributedString(
                string: label,
                attributes: [
                    .font: NSFont.boldSystemFont(ofSize: StatusItemGlyph.Metrics.beaconFontSize),
                    .foregroundColor: NSColor.white,
                    .paragraphStyle: paragraph,
                ]
            )
            let textSize = text.size()
            text.draw(
                at: NSPoint(
                    x: center.x - textSize.width / 2,
                    y: center.y - textSize.height / 2 + 0.5
                ))
            return true
        }
        image.isTemplate = false
        return image
    }
}

/// Mouse-transparent overlay for the colored badge. The status-item button
/// continues to own the template glyph and all click/accessibility behavior.
@MainActor
final class StatusItemBeaconAccessoryView: NSView {
    var count = 0 {
        didSet {
            isHidden = count <= 0
            needsDisplay = true
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isHidden = true
        autoresizingMask = [.width, .height]
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func draw(_ dirtyRect: NSRect) {
        guard count > 0 else { return }
        let canvas = StatusItemGlyph.Metrics.canvasLength
        let glyphRect = NSRect(
            x: (bounds.width - canvas) / 2,
            y: (bounds.height - canvas) / 2,
            width: canvas,
            height: canvas
        )
        StatusItemBeaconGlyph.image(count: count).draw(in: glyphRect)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}

/// The one-shot swell of the bullet after a capture lands.
enum StatusItemPulse {
    /// Total pulse length.
    static let duration: Duration = .milliseconds(420)
    /// Frames in one pulse.
    static let frameCount = 24
    /// Bullet radius at the swell peak, leaving a 1.1pt gap to the counter.
    static let peakBulletRadius: CGFloat = 2.9
    /// Interval between frames: `duration / frameCount` (17.5 ms).
    static let frameInterval: Duration = .nanoseconds(17_500_000)

    /// Radius at progress `t` in [0, 1]: `1.6 + 1.3 * sin(pi * t)`.
    static func bulletRadius(atProgress progress: Double) -> CGFloat {
        let clamped = min(max(progress, 0), 1)
        guard clamped > 0, clamped < 1 else {
            return StatusItemGlyph.Metrics.bulletRadius
        }
        let hump = 1.3 * sin(Double.pi * clamped)
        return StatusItemGlyph.Metrics.bulletRadius + CGFloat(hump)
    }

    /// `frameCount + 1` samples; the first and last equal the resting radius.
    static var bulletRadii: [CGFloat] {
        (0...frameCount).map {
            bulletRadius(atProgress: Double($0) / Double(frameCount))
        }
    }
}

/// The strings and glyph state for one resolution of `bob` plus the wake
/// beacon, testable without a real `NSStatusItem`.
struct StatusItemPresentation: Equatable {
    let glyphState: StatusItemGlyph.State
    let toolTip: String
    let accessibilityLabel: String
    /// The conditional first menu row; nil while healthy.
    let issueMenuTitle: String?
    /// Unacknowledged delivered wake tasks. Zero hides the beacon.
    let snoozeCount: Int

    init(isBobResolved: Bool, snoozeCount: Int = 0) {
        let count = max(0, snoozeCount)
        self.snoozeCount = count
        if isBobResolved {
            glyphState = .ready
            issueMenuTitle = nil
        } else {
            glyphState = .bobUnresolved
            issueMenuTitle = "bob Not Resolved — Open Settings…"
        }
        let beaconSuffix: String = {
            guard count > 0 else { return "" }
            return count == 1
                ? " — 1 snoozed task ready"
                : " — \(count) snoozed tasks ready"
        }()
        let beaconAccessibilitySuffix: String = {
            guard count > 0 else { return "" }
            return count == 1
                ? ", 1 snoozed task ready"
                : ", \(count) snoozed tasks ready"
        }()
        if isBobResolved {
            toolTip = "Bob Mac Capture\(beaconSuffix)"
            accessibilityLabel = "Bob Mac Capture\(beaconAccessibilitySuffix)"
        } else {
            let baseTip = "Bob Mac Capture — bob is not resolved. Check Settings."
            let baseLabel = "Bob Mac Capture, bob not resolved"
            toolTip = "\(baseTip)\(beaconSuffix)"
            accessibilityLabel = "\(baseLabel)\(beaconAccessibilitySuffix)"
        }
    }
}

/// The value handed to the renderer: everything above it stays testable without
/// a real `NSStatusItem`.
struct StatusItemFrame: Equatable {
    let glyphState: StatusItemGlyph.State
    let bulletRadius: CGFloat
    let toolTip: String
    let accessibilityLabel: String
    /// Unacknowledged delivered wake tasks rendered with the frame.
    let snoozeCount: Int
}
