import Foundation

/// The item kind named by a copy picker scope and count.
public enum RefsPickerNoun: Equatable, Sendable {
    case codeBlock
    case link
    case highlight

    public var countCaptionSingular: String {
        switch self {
        case .codeBlock: "CODE BLOCK"
        case .link: "LINK"
        case .highlight: "HIGHLIGHT"
        }
    }

    public var countCaptionPlural: String {
        switch self {
        case .codeBlock: "CODE BLOCKS"
        case .link: "LINKS"
        case .highlight: "HIGHLIGHTS"
        }
    }

    public var ordinalWord: String {
        switch self {
        case .codeBlock: "Block"
        case .link: "Link"
        case .highlight: "Highlight"
        }
    }

    public var voiceOverNoun: String {
        switch self {
        case .codeBlock: "Code block"
        case .link: "Link"
        case .highlight: "Highlight"
        }
    }

    public var spokenPlural: String {
        switch self {
        case .codeBlock: "code blocks"
        case .link: "links"
        case .highlight: "highlights"
        }
    }

    public var spokenSingular: String {
        switch self {
        case .codeBlock: "code block"
        case .link: "link"
        case .highlight: "highlight"
        }
    }

    public func spokenNoun(count: Int) -> String {
        count == 1 ? spokenSingular : spokenPlural
    }
}

/// The selection and visible range shared by every copy picker.
public struct RefsPickerScope: Equatable, Sendable {
    public let noun: RefsPickerNoun
    public let total: Int
    public let selectedIndex: Int
    public let visibleStart: Int
    public let visibleCount: Int
    public let onPageIndices: [Int]

    public init(
        noun: RefsPickerNoun,
        total: Int,
        selectedIndex: Int,
        visibleStart: Int,
        visibleCount: Int,
        onPageIndices: [Int] = []
    ) {
        self.noun = noun
        self.total = max(0, total)
        self.selectedIndex = min(max(0, selectedIndex), max(0, total - 1))
        self.visibleStart = min(max(0, visibleStart), max(0, total - 1))
        self.visibleCount = min(max(0, visibleCount), max(0, total - self.visibleStart))
        self.onPageIndices = Array(Set(onPageIndices.filter { (0..<max(0, total)).contains($0) }))
            .sorted()
    }

    public var isWindowed: Bool { visibleCount < total }

    /// One-based inclusive range of entries represented by the digit keycaps.
    public var visibleRange: ClosedRange<Int>? {
        guard visibleCount > 0 else { return nil }
        return (visibleStart + 1)...(visibleStart + visibleCount)
    }

    public var selectedOrdinal: Int { selectedIndex + 1 }

    public var countCaption: String {
        "\(total) \(total == 1 ? noun.countCaptionSingular : noun.countCaptionPlural)"
    }

    public var ordinalLabel: String {
        "\(noun.ordinalWord) \(selectedOrdinal) of \(total)"
    }

    public var scopeLabel: String? {
        guard total > 1 else { return nil }
        guard isWindowed, let range = visibleRange else { return "all shown" }
        if range.lowerBound == range.upperBound {
            return "showing \(range.lowerBound)"
        }
        return "showing \(range.lowerBound)–\(range.upperBound)"
    }

    public var accessibilityScopeLabel: String? {
        guard let range = visibleRange, total > 1 else { return nil }
        guard isWindowed else { return "all shown" }
        if range.lowerBound == range.upperBound {
            return "showing \(range.lowerBound)"
        }
        return "showing \(range.lowerBound) to \(range.upperBound)"
    }

    public var digitRangeText: String {
        visibleCount <= 1 ? "1" : "1–\(visibleCount)"
    }

    public var pickHint: String {
        "\(digitRangeText) \(visibleCount == 1 ? "picks" : "pick")"
    }

    public var digitMissMessage: String {
        let verb = visibleCount == 1 ? "is" : "are"
        let action = isWindowed ? "showing · ↑↓ scrolls" : "listed"
        return "Only \(digitRangeText) \(verb) \(action)"
    }

    public var accessibilityLabel: String {
        var label = "\(noun.voiceOverNoun) \(selectedOrdinal) of \(total)"
        if let accessibilityScopeLabel {
            label += ", \(accessibilityScopeLabel)"
        }
        return label
    }
}

/// Pure placement data for the non-interactive overview rail.
public struct RefsPickerRailGeometry: Equatable, Sendable {
    public let scope: RefsPickerScope
    public let trackHeight: Double
    public let thumb: ClosedRange<Double>
    public let selectedY: Double
    public let ticks: [ClosedRange<Double>]

    public static func make(
        scope: RefsPickerScope,
        trackHeight: Double,
        minimumThumbHeight: Double,
        tickHalfHeight: Double
    ) -> Self? {
        let total = scope.total
        let visible = scope.visibleCount
        guard scope.isWindowed, total > 0, visible > 0, trackHeight > 0 else { return nil }

        let height = min(
            trackHeight,
            max(max(0, minimumThumbHeight), trackHeight * Double(visible) / Double(total))
        )
        let maxStart = total - visible
        let top =
            maxStart > 0
            ? (trackHeight - height) * Double(scope.visibleStart) / Double(maxStart)
            : 0
        let bottom = top + height
        let thumb = top...bottom

        func y(for index: Int) -> Double? {
            guard (0..<total).contains(index) else { return nil }
            if index < scope.visibleStart {
                let beforeCount = scope.visibleStart
                guard beforeCount > 0 else { return nil }
                return top * (Double(index) + 0.5) / Double(beforeCount)
            }
            if index < scope.visibleStart + visible {
                return top + height * (Double(index - scope.visibleStart) + 0.5)
                    / Double(visible)
            }
            let afterStart = scope.visibleStart + visible
            let afterCount = total - afterStart
            guard afterCount > 0 else { return nil }
            return bottom + (trackHeight - bottom)
                * (Double(index - afterStart) + 0.5) / Double(afterCount)
        }

        let selectedY = y(for: scope.selectedIndex) ?? (top + height / 2)
        let half = max(0, tickHalfHeight)
        let rawTicks = scope.onPageIndices.compactMap { index -> ClosedRange<Double>? in
            guard let center = y(for: index) else { return nil }
            return max(0, center - half)...min(trackHeight, center + half)
        }.sorted { $0.lowerBound < $1.lowerBound }
        var ticks: [ClosedRange<Double>] = []
        for tick in rawTicks {
            if let last = ticks.last, tick.lowerBound <= last.upperBound {
                ticks[ticks.count - 1] = last.lowerBound...max(last.upperBound, tick.upperBound)
            } else {
                ticks.append(tick)
            }
        }

        return Self(
            scope: scope,
            trackHeight: trackHeight,
            thumb: thumb,
            selectedY: selectedY,
            ticks: ticks
        )
    }

    public func y(forIndex index: Int) -> Double? {
        guard (0..<scope.total).contains(index) else { return nil }
        let top = thumb.lowerBound
        let height = thumb.upperBound - top
        let visible = scope.visibleCount
        if index < scope.visibleStart {
            let beforeCount = scope.visibleStart
            guard beforeCount > 0 else { return nil }
            return top * (Double(index) + 0.5) / Double(beforeCount)
        }
        if index < scope.visibleStart + visible {
            return top + height * (Double(index - scope.visibleStart) + 0.5) / Double(visible)
        }
        let bottom = thumb.upperBound
        let afterStart = scope.visibleStart + visible
        let afterCount = scope.total - afterStart
        guard afterCount > 0 else { return nil }
        return bottom + (trackHeight - bottom)
            * (Double(index - afterStart) + 0.5) / Double(afterCount)
    }
}
