import AppKit
import CaptureCore
import SwiftUI

extension CapturePanelLayout {
    static let inboxRouteBarHeight: CGFloat = 46
    static let inboxRouteContextHeight: CGFloat = 34
    static let inboxRouteRowHeight: CGFloat = 52
    static let inboxRouteListPadding: CGFloat = 6
    static let inboxRouteMaxVisibleRows = 6
    static let inboxRouteMinVisibleRows = 2
}

struct CaptureInboxRouteChoiceHeightPolicy: Equatable {
    var rowCount: Int
    var displayScale: CGFloat = 1

    init(rowCount: Int, displayScale: CGFloat = 1) {
        self.rowCount = rowCount
        self.displayScale = displayScale
    }

    init(choice: CaptureInboxRouteChoiceState, displayScale: CGFloat = 1) {
        self.init(rowCount: choice.destinations.count, displayScale: displayScale)
    }

    var listContentHeight: CGFloat {
        roundedToPixel(
            CapturePanelLayout.inboxRouteListPadding * 2
                + CGFloat(max(rowCount, 1)) * CapturePanelLayout.inboxRouteRowHeight
        )
    }

    var maxListHeight: CGFloat {
        roundedToPixel(
            CapturePanelLayout.inboxRouteListPadding * 2
                + CGFloat(CapturePanelLayout.inboxRouteMaxVisibleRows)
                    * CapturePanelLayout.inboxRouteRowHeight
        )
    }

    var minListHeight: CGFloat {
        roundedToPixel(
            CapturePanelLayout.inboxRouteListPadding * 2
                + CGFloat(CapturePanelLayout.inboxRouteMinVisibleRows)
                    * CapturePanelLayout.inboxRouteRowHeight
        )
    }

    var listViewportHeight: CGFloat {
        min(listContentHeight, maxListHeight)
    }

    var idealHeight: CGFloat {
        roundedToPixel(
            CapturePanelLayout.inboxRouteBarHeight
                + CapturePanelLayout.inboxRouteContextHeight
                + 1
                + listViewportHeight
        )
    }

    var minimumVisibleHeight: CGFloat {
        roundedToPixel(
            CapturePanelLayout.inboxRouteBarHeight
                + CapturePanelLayout.inboxRouteContextHeight
                + 1
                + min(listContentHeight, minListHeight)
        )
    }

    private func roundedToPixel(_ value: CGFloat) -> CGFloat {
        let scale = max(displayScale, 1)
        return (value * scale).rounded(.up) / scale
    }
}

@available(macOS 26.0, *)
struct CaptureInboxRouteChoiceCard: View {
    @ObservedObject var model: CapturePanelModel
    let choice: CaptureInboxRouteChoiceState
    var previewMode = false
    @Environment(\.displayScale) private var displayScale

    private var policy: CaptureInboxRouteChoiceHeightPolicy {
        CaptureInboxRouteChoiceHeightPolicy(choice: choice, displayScale: displayScale)
    }

    var body: some View {
        VStack(spacing: 0) {
            filterBar
                .frame(height: CapturePanelLayout.inboxRouteBarHeight)
            contextLine
                .frame(height: CapturePanelLayout.inboxRouteContextHeight)
            Divider()
            if previewMode {
                routeRows
                    .frame(height: policy.listViewportHeight, alignment: .top)
                    .clipped()
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.vertical) {
                        LazyVStack(spacing: 2) {
                            destinationRows
                            if choice.filteredDestinations.isEmpty {
                                emptyState
                            }
                        }
                        .padding(CapturePanelLayout.inboxRouteListPadding)
                    }
                    .frame(height: policy.listViewportHeight)
                    .onChange(of: choice.highlightedRow?.relativePath) { _, path in
                        guard let path else { return }
                        proxy.scrollTo(path, anchor: nil)
                    }
                }
            }
        }
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: CapturePanelLayout.pickerCornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: CapturePanelLayout.pickerCornerRadius)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
        .shadow(radius: 18, y: 8)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Inbox route choices")
        .focusable()
        .focusEffectDisabled()
    }

    private var filterBar: some View {
        HStack(spacing: 8) {
            HStack(spacing: 4) {
                Image(systemName: "tray.and.arrow.up")
                    .accessibilityHidden(true)
                Text("Route out of \(choice.currentCandidate?.inbox ?? "inbox")")
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.background.opacity(0.45), in: Capsule())

            if previewMode {
                Text(choice.filterText.isEmpty ? "Where does this go?" : choice.filterText)
                    .font(.system(size: 15))
                    .foregroundStyle(choice.filterText.isEmpty ? .tertiary : .primary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                CapturePickerFilterField(
                    text: choice.filterText,
                    placeholder: "Where does this go? Filter areas and open projects",
                    accessibilityLabel: "Filter route destinations",
                    focusRequest: model.focusRequest,
                    onTextChange: { model.updateInboxRouteChoiceFilter($0) },
                    fieldIdentifier: inboxRouteFilterFieldAccessibilityIdentifier,
                    focusTarget: .inboxRouteFilter,
                    onFocusChange: { focused in
                        if focused {
                            model.focusInboxRouteChoiceFilter()
                        }
                    }
                )
                .frame(maxWidth: .infinity)
            }

            Text(countText)
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
                .fixedSize()
        }
        .padding(.horizontal, 10)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Route destination filter")
    }

    private var contextLine: some View {
        HStack(spacing: 6) {
            if choice.refusalMessage != nil {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(.red)
                    .accessibilityHidden(true)
            }
            if let candidate = choice.currentCandidate {
                Text(
                    CaptureInboxRoutePresentation.contextLine(
                        candidate: candidate,
                        index: choice.cursor,
                        total: choice.candidates.count,
                        refusalMessage: choice.refusalMessage
                    )
                )
                .font(.caption)
                .foregroundStyle(choice.refusalMessage == nil ? Color.primary : Color.red)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 12)
        .accessibilityElement(children: .combine)
    }

    private var routeRows: some View {
        VStack(spacing: 2) {
            destinationRows
            if choice.filteredDestinations.isEmpty {
                emptyState
            }
        }
        .padding(CapturePanelLayout.inboxRouteListPadding)
    }

    private var destinationRows: some View {
        ForEach(choice.filteredDestinations, id: \.relativePath) { destination in
            destinationRow(destination)
                .id(destination.relativePath)
        }
    }

    private func destinationRow(_ destination: CaptureInboxRouteDestination) -> some View {
        let highlighted = choice.highlightedRow?.relativePath == destination.relativePath
        return Button {
            model.selectInboxRouteDestination(destination.relativePath)
        } label: {
            HStack(spacing: 9) {
                Image(systemName: destination.kind == "project" ? "folder" : "square.stack")
                    .foregroundStyle(highlighted ? Color.accentColor : Color.secondary)
                    .frame(width: 18)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(CaptureInboxRoutePresentation.rowText(destination: destination))
                        .font(.callout.weight(highlighted ? .semibold : .regular))
                        .lineLimit(1)
                    Text(CaptureInboxRoutePresentation.rowPathDetail(destination: destination))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                if destination.status == "wip" || destination.status == "waiting" {
                    Text(destination.status ?? "")
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(.background.opacity(0.65), in: Capsule())
                }
                if destination.blocked {
                    Label("Blocked", systemImage: "lock.fill")
                        .font(.caption2.weight(.medium))
                        .labelStyle(.titleAndIcon)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(.orange.opacity(0.14), in: Capsule())
                }
            }
            .padding(.horizontal, 9)
            .frame(height: CapturePanelLayout.inboxRouteRowHeight - 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                if highlighted {
                    RoundedRectangle(cornerRadius: 7)
                        .fill(Color.accentColor.opacity(0.14))
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            "\(destination.label), \(CaptureInboxRoutePresentation.rowDetail(destination: destination))"
        )
        .accessibilityAddTraits(highlighted ? .isSelected : [])
    }

    private var emptyState: some View {
        Text("No matching destinations")
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: CapturePanelLayout.inboxRouteRowHeight * 2)
            .accessibilityLabel("No matching destinations")
    }

    private var countText: String {
        if choice.filterText.isEmpty {
            return "\(choice.destinations.count) destinations"
        }
        return "\(choice.filteredDestinations.count) of \(choice.destinations.count)"
    }
}

struct CaptureInboxRouteChoiceFooter: View {
    @ObservedObject var model: CapturePanelModel

    static let hintItems: [(keys: String, action: String)] = [
        ("↑↓ ⌃N ⌃P", "Move"),
        ("esc", "Back"),
        ("⌃↩", "Move & Open"),
    ]

    static let accessibilityText =
        "Up, Down, Control-N, or Control-P moves the highlighted destination. Return moves the task to the highlighted destination. Shift-Return keeps it in its inbox. Control-Return moves it and opens the capture notes. Escape goes back one task, then to the previous successor choice or the draft."

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            ViewThatFits(in: .horizontal) {
                hintRow(items: Self.hintItems)
                hintRow(items: Array(Self.hintItems.dropLast()))
            }
            Spacer(minLength: 12)
            Button {
                model.keepInboxRouteCandidate()
            } label: {
                HStack(spacing: 4) {
                    Text("Keep in inbox")
                    Text("⇧↩")
                        .opacity(0.7)
                }
            }
            .buttonStyle(CapturePullInActionButtonStyle(prominent: false))
            .disabled(model.isSubmitting)
            Button {
                model.confirmInboxRouteChoice()
            } label: {
                HStack(spacing: 4) {
                    Text("Move")
                    Text("↩")
                        .opacity(0.7)
                }
            }
            .buttonStyle(CapturePullInActionButtonStyle(prominent: true))
            .disabled(model.isSubmitting || model.inboxRouteChoice?.highlightedRow == nil)
        }
        .frame(minHeight: 28)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Self.accessibilityText)
        .onChange(of: model.statusAnnouncementTick) { _, _ in
            guard !model.statusText.isEmpty else { return }
            AccessibilityNotification.Announcement(model.statusText).post()
        }
    }

    private func hintRow(items: [(keys: String, action: String)]) -> some View {
        HStack(spacing: 12) {
            ForEach(0..<items.count, id: \.self) { index in
                HStack(spacing: 4) {
                    Text(items[index].keys)
                        .font(.caption.monospaced())
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            .background.opacity(0.6),
                            in: RoundedRectangle(cornerRadius: 4)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5)
                        )
                    Text(items[index].action)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
