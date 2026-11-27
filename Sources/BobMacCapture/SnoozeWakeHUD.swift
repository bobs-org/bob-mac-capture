import AppKit
import CaptureCore
import Combine
import SwiftUI

final class SnoozeWakeHUDPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

@MainActor
final class SnoozeWakeHUDState: ObservableObject {
    @Published var batch: SnoozeWakeNoticeBatch
    @Published var presentation: SnoozeWakeNoticePresentation
    @Published var isSnoozing = false
    @Published var feedback: String?
    @Published var headlineOverride: String?
    @Published var secondsRemaining = SnoozeWakeNoticePresentation.hudDisplaySeconds

    init(batch: SnoozeWakeNoticeBatch, presentation: SnoozeWakeNoticePresentation) {
        self.batch = batch
        self.presentation = presentation
    }

    var headline: String {
        headlineOverride ?? presentation.headline
    }
}

/// Interactive, non-activating HUD for one delivered snooze batch.
@MainActor
final class SnoozeWakeHUDController {
    static let maximumWidth: CGFloat = 520
    static let edgeInset: CGFloat = 18

    var onAcknowledge: (String) -> Void = { _ in }
    var onTasksRemoved: (String, [String]) -> Void = { _, _ in }
    var onTransientEnded: (String) -> Void = { _ in }

    private let processClient: () -> BobProcessClient?
    private let vaultRoot: () -> String
    private let today: () -> String
    private let refreshAgenda: () -> Void
    private let chimeEnabled: () -> Bool
    private let reduceMotion: () -> Bool
    private let openURL: (URL) -> Bool
    private let playChime: () -> Void
    private var panel: SnoozeWakeHUDPanel?
    private var hostingView: FirstMouseHostingView<SnoozeWakeHUDView>?
    private var state: SnoozeWakeHUDState?
    private var dismissalTask: Task<Void, Never>?
    private var visibleUntil: Date?
    private var hovered = false
    private var generation: UInt64 = 0
    private var currentWakeID: String?
    private var soundedWakeIDs: Set<String> = []
    private var pendingBatch: (SnoozeWakeNoticeBatch, SnoozeWakeNoticePresentation)?

    init(
        processClient: @escaping () -> BobProcessClient?,
        vaultRoot: @escaping () -> String,
        today: @escaping () -> String = { CaptureAgendaStore.localToday() },
        refreshAgenda: @escaping () -> Void,
        chimeEnabled: @escaping () -> Bool,
        reduceMotion: @escaping () -> Bool = {
            NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        },
        openURL: @escaping (URL) -> Bool = { NSWorkspace.shared.open($0) },
        playChime: @escaping () -> Void = { NSSound(named: "Pop")?.play() }
    ) {
        self.processClient = processClient
        self.vaultRoot = vaultRoot
        self.today = today
        self.refreshAgenda = refreshAgenda
        self.chimeEnabled = chimeEnabled
        self.reduceMotion = reduceMotion
        self.openURL = openURL
        self.playChime = playChime
    }

    func show(
        batch: SnoozeWakeNoticeBatch, presentation: SnoozeWakeNoticePresentation,
        silent: Bool = false
    ) {
        let isNewWake = currentWakeID != batch.wakeID
        // A new batch arriving while +15m is in flight must not inherit the
        // in-flight feedback: queue it until the action settles.
        if isNewWake, let current = state, current.isSnoozing {
            pendingBatch = (batch, presentation)
            return
        }
        let needsOrderIn = panel?.isVisible != true
        let isSameVisibleWake = !isNewWake && !needsOrderIn
        currentWakeID = batch.wakeID
        generation &+= 1
        let expectedGeneration = generation
        dismissalTask?.cancel()
        if !isSameVisibleWake {
            hovered = false
        }
        let model = state ?? SnoozeWakeHUDState(batch: batch, presentation: presentation)
        model.batch = batch
        model.presentation = presentation
        if !isSameVisibleWake {
            model.feedback = nil
            model.headlineOverride = nil
            model.isSnoozing = false
            model.secondsRemaining = SnoozeWakeNoticePresentation.hudDisplaySeconds
        }
        state = model

        let screenFrame =
            GlassPanelHost.visibleFrameAtPointer()
            ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        let preferredWidth = min(Self.maximumWidth, max(240, screenFrame.width - 40))
        let created = panel ?? Self.makePanel()
        panel = created
        let view = SnoozeWakeHUDView(
            state: model,
            reduceMotion: reduceMotion(),
            maximumWidth: preferredWidth,
            onOpen: { [weak self] row in self?.open(row: row, wakeID: batch.wakeID) },
            onSnooze: { [weak self] in self?.snoozeRemaining(wakeID: batch.wakeID) },
            onDismiss: { [weak self] in self?.dismiss(wakeID: batch.wakeID) },
            onHover: { [weak self] isHovering in self?.setHovered(isHovering) }
        )
        if let hostingView {
            hostingView.rootView = view
        } else {
            let hosting = FirstMouseHostingView(rootView: view)
            hosting.sizingOptions = [.intrinsicContentSize]
            hostingView = hosting
        }
        guard let hostingView else { return }
        hostingView.layoutSubtreeIfNeeded()
        var size = hostingView.fittingSize
        if size.width < 1 || size.height < 1 {
            size = NSSize(width: preferredWidth, height: 180)
        }
        size.width = min(preferredWidth, max(min(280, preferredWidth), size.width))
        size.height = min(max(120, size.height), max(120, screenFrame.height - 40))
        GlassPanelHost.install(
            content: hostingView,
            size: size,
            in: created,
            reduceTransparency: NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency,
            opaqueCornerRadius: 24,
            glassCornerRadius: 24
        )
        created.setFrame(
            GlassPanelHost.frame(
                size: size,
                placement: .topCenter(in: screenFrame, inset: Self.edgeInset)
            ),
            display: true
        )
        created.alphaValue = 1
        created.orderFrontRegardless()

        if !silent {
            if isNewWake, soundedWakeIDs.insert(batch.wakeID).inserted {
                if soundedWakeIDs.count > SnoozeWakeHandledStore.maxEntries,
                    let oldest = soundedWakeIDs.first
                {
                    soundedWakeIDs.remove(oldest)
                }
                if chimeEnabled() {
                    playChime()
                }
            }
            if isNewWake || needsOrderIn {
                announce(model.headline, on: created)
            }
        }
        startCountdown(generation: expectedGeneration)
    }

    /// Restores a hold-hidden HUD without a chime, announcement, or record
    /// re-post. Only the HUD that the hold hid while on screen is restored;
    /// the coordinator filters ended wakes before calling here.
    func restore(batch: SnoozeWakeNoticeBatch, presentation: SnoozeWakeNoticePresentation) {
        show(batch: batch, presentation: presentation, silent: true)
    }

    /// Hides task copy without acknowledging the delivered wake. The
    /// coordinator can revalidate and show it again after a hold clears.
    func dismissTransient() {
        cancelCountdown()
        panel?.orderOut(nil)
    }

    func dismissTransient(wakeID: String) {
        guard currentWakeID == wakeID else { return }
        dismissTransient()
    }

    func dismiss() {
        generation &+= 1
        cancelCountdown()
        panel?.alphaValue = 0
        panel?.orderOut(nil)
    }

    func dismiss(wakeID: String) {
        guard currentWakeID == wakeID else { return }
        let endedID = currentWakeID
        dismiss()
        if let endedID {
            onTransientEnded(endedID)
        }
        drainPending()
    }

    /// The countdown firing ends the transient nudge, keyed by wake ID, so
    /// the coordinator never re-presents it after a later hold.
    private func endNudgeForTimeout() {
        guard let endedID = currentWakeID else {
            dismiss()
            return
        }
        dismiss()
        onTransientEnded(endedID)
        drainPending()
    }

    private func drainPending() {
        guard let next = pendingBatch else { return }
        pendingBatch = nil
        show(batch: next.0, presentation: next.1)
    }

    static func makePanel() -> SnoozeWakeHUDPanel {
        let panel = SnoozeWakeHUDPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 180),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        GlassPanelHost.configure(panel, interaction: .interactive)
        panel.sharingType = .none
        return panel
    }

    static func validatedTaskURL(
        row: SnoozeWakeListRow, vaultRoot: String
    ) -> URL? {
        guard let route = validatedRoute(row.route, vaultRoot: vaultRoot),
            let line = row.line, line > 0,
            let rawBlockID = row.blockID, !rawBlockID.isEmpty
        else {
            return nil
        }
        let blockID = rawBlockID.hasPrefix("^") ? String(rawBlockID.dropFirst()) : rawBlockID
        return ObsidianOpenURL.taskGotoURL(path: route.path, line: line, ref: nil, blockID: blockID)
    }

    static func validatedRoute(_ route: String?, vaultRoot: String) -> URL? {
        guard let route, !route.isEmpty, !route.hasPrefix("/"),
            !route.contains("\\"), !route.contains(":"),
            !route.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
        else {
            return nil
        }
        let components = route.split(separator: "/", omittingEmptySubsequences: false)
        guard !components.isEmpty,
            components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." })
        else {
            return nil
        }
        let root = URL(fileURLWithPath: vaultRoot, isDirectory: true)
            .standardizedFileURL.resolvingSymlinksInPath()
        let file = root.appendingPathComponent(route).standardizedFileURL
            .resolvingSymlinksInPath()
        let prefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
        guard file.path.hasPrefix(prefix) else { return nil }
        return file
    }

    private func open(row: SnoozeWakeListRow, wakeID: String) {
        guard currentWakeID == wakeID else { return }
        guard let url = Self.validatedTaskURL(row: row, vaultRoot: vaultRoot()),
            openURL(url)
        else {
            state?.feedback = "Couldn't open this task in Obsidian."
            return
        }
        pendingBatch = nil
        dismiss()
        onAcknowledge(wakeID)
    }

    private func snoozeRemaining(wakeID: String) {
        guard let state, state.batch.wakeID == wakeID, !state.isSnoozing else { return }
        state.isSnoozing = true
        state.feedback = nil
        state.headlineOverride = nil
        Task { [weak self, weak state] in
            guard let self, let state else { return }
            await self.performSnooze(state: state, wakeID: wakeID)
            await MainActor.run {
                state.isSnoozing = false
                self.drainPending()
            }
        }
    }

    private func performSnooze(state: SnoozeWakeHUDState, wakeID: String) async {
        guard let client = processClient() else {
            state.feedback = "Bob isn't available. These tasks are still ready."
            return
        }
        let batch = state.batch
        let root = vaultRoot()
        let rootURL = URL(fileURLWithPath: root, isDirectory: true)
            .standardizedFileURL.resolvingSymlinksInPath()
        guard today() == batch.date,
            let configuredRoot = batch.vaultRoot,
            URL(fileURLWithPath: configuredRoot, isDirectory: true)
                .standardizedFileURL.resolvingSymlinksInPath().path == rootURL.path
        else {
            state.feedback = "The vault or day changed. These tasks remain ready."
            return
        }

        let oldRows = state.batch.rows.filter { $0.identityKey != nil }
        do {
            let response = try await client.snoozeListForWakeVerification()
            guard response.supportsWakeNotice, response.date == batch.date,
                let responseRoot = response.vaultRoot,
                URL(fileURLWithPath: responseRoot, isDirectory: true)
                    .standardizedFileURL.resolvingSymlinksInPath().path == rootURL.path
            else {
                state.feedback = "Bob couldn't verify these tasks. They are still ready."
                return
            }
            let current = Dictionary(
                response.eligibleRows.compactMap { row in
                    row.identityKey.map { ($0, row) }
                },
                uniquingKeysWith: { first, _ in first }
            )
            let verified = oldRows.filter { old in
                guard let key = old.identityKey, let fresh = current[key] else { return false }
                return fresh.target == old.target && fresh.wokeAt == old.wokeAt
                    && fresh.route == old.route && fresh.blockID == old.blockID
            }
            let verifiedKeys = Set(verified.compactMap(\.identityKey))
            let staleKeys = oldRows.compactMap(\.identityKey).filter { !verifiedKeys.contains($0) }
            if !staleKeys.isEmpty {
                removeRows(staleKeys, from: state, wakeID: wakeID)
            }
            guard !verified.isEmpty else {
                state.feedback = "These tasks changed and are no longer ready."
                refreshAgenda()
                return
            }

            var successfulKeys: [String] = []
            var labels: [String] = []
            var failedCount = 0
            var refusalMessage: String?
            for row in verified {
                guard today() == batch.date,
                    let key = row.identityKey,
                    Self.validatedRoute(row.route, vaultRoot: root) != nil,
                    let route = row.route,
                    let blockID = row.blockID, !blockID.isEmpty
                else {
                    failedCount += 1
                    continue
                }
                do {
                    let result = try await client.snoozeAdd(route: route, blockID: blockID)
                    if result.didWrite {
                        successfulKeys.append(key)
                        if let label = result.snoozedUntilLabel, !label.isEmpty {
                            labels.append(label)
                        }
                    } else {
                        failedCount += 1
                    }
                } catch let error as BobClientError {
                    failedCount += 1
                    if case .snoozeRefused(_, let message) = error {
                        refusalMessage = refusalMessage ?? message
                    }
                } catch {
                    failedCount += 1
                }
            }
            if !successfulKeys.isEmpty {
                removeRows(successfulKeys, from: state, wakeID: wakeID)
                refreshAgenda()
            }
            if failedCount > 0 {
                if let refusalMessage {
                    state.feedback =
                        successfulKeys.isEmpty
                        ? refusalMessage
                        : "Snoozed \(successfulKeys.count); \(refusalMessage)"
                    state.headlineOverride = nil
                } else {
                    state.feedback =
                        successfulKeys.isEmpty
                        ? "Couldn't snooze these tasks. They are still ready."
                        : "Snoozed \(successfulKeys.count); \(failedCount) still ready."
                    state.headlineOverride = nil
                }
            } else if let label = labels.first, Set(labels).count == 1 {
                state.feedback = "Snoozed until \(label)"
                state.headlineOverride = "Snoozed until \(label)"
            } else {
                state.feedback = "Snoozed \(successfulKeys.count) tasks"
                state.headlineOverride = "Snoozed \(successfulKeys.count) tasks"
            }
        } catch {
            state.feedback = "Couldn't verify these tasks. They are still ready."
        }
    }

    private func removeRows(
        _ keys: [String], from state: SnoozeWakeHUDState, wakeID: String
    ) {
        let removed = Set(keys)
        state.batch = SnoozeWakeNoticeBatch(
            wakeID: state.batch.wakeID,
            wokenAt: state.batch.wokenAt,
            date: state.batch.date,
            rows: state.batch.rows.filter { row in
                guard let key = row.identityKey else { return false }
                return !removed.contains(key)
            },
            vaultRoot: state.batch.vaultRoot,
            receiptTasks: state.batch.receiptTasks
        )
        state.presentation = SnoozeWakeNoticePresentation(
            batch: state.batch,
            listBudget: state.presentation.listBudget,
            announcement: state.presentation.announcement
        )
        onTasksRemoved(wakeID, keys)
    }

    private func setHovered(_ isHovering: Bool) {
        guard hovered != isHovering else { return }
        hovered = isHovering
        if isHovering {
            if let visibleUntil {
                state?.secondsRemaining = max(0, visibleUntil.timeIntervalSinceNow)
            }
            cancelCountdown()
        } else {
            startCountdown(generation: generation)
        }
    }

    private func startCountdown(generation expected: UInt64) {
        guard !hovered else { return }
        let remaining = max(0.1, state?.secondsRemaining ?? 0)
        visibleUntil = Date().addingTimeInterval(remaining)
        dismissalTask?.cancel()
        dismissalTask = Task { [weak self] in
            let deadline = Date().addingTimeInterval(remaining)
            while !Task.isCancelled {
                let left = deadline.timeIntervalSinceNow
                guard left > 0 else { break }
                await MainActor.run {
                    guard let self, self.generation == expected else { return }
                    self.state?.secondsRemaining = left
                }
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
            guard !Task.isCancelled else { return }
            await MainActor.run { [weak self] in
                guard let self, self.generation == expected else { return }
                self.endNudgeForTimeout()
            }
        }
    }

    private func cancelCountdown() {
        dismissalTask?.cancel()
        dismissalTask = nil
        visibleUntil = nil
    }

    private func announce(_ message: String, on panel: NSPanel) {
        // VoiceOver tracks views, not the non-key panel itself: announce
        // against the hosted content when it exists so the request is
        // spoken for a non-activating panel.
        let element: Any = hostingView ?? panel
        NSAccessibility.post(
            element: element,
            notification: .announcementRequested,
            userInfo: [
                .announcement: message,
                .priority: NSAccessibilityPriorityLevel.high.rawValue,
            ]
        )
    }
}

@MainActor
struct SnoozeWakeHUDView: View {
    @ObservedObject var state: SnoozeWakeHUDState
    let reduceMotion: Bool
    var maximumWidth: CGFloat = SnoozeWakeHUDController.maximumWidth
    let onOpen: (SnoozeWakeListRow) -> Void
    let onSnooze: () -> Void
    let onDismiss: () -> Void
    let onHover: (Bool) -> Void
    @State private var animationTick = false

    private var rows: [SnoozeWakeListRow] { state.batch.rows }
    private var overCap: Bool { state.presentation.isOverCap }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "alarm")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(overCap ? Color.orange : Color.accentColor)
                    .accessibilityHidden(true)
                    .modifier(AlarmMotion(enabled: !reduceMotion, value: animationTick))
                VStack(alignment: .leading, spacing: 4) {
                    Text(state.headline)
                        .font(.system(size: 14, weight: .semibold))
                        .fixedSize(horizontal: false, vertical: true)
                        .lineLimit(2)
                        .accessibilityAddTraits(.isHeader)
                    Button {
                        if let first = rows.first { onOpen(first) }
                    } label: {
                        subtitleText
                            .font(.system(size: 11.5))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .buttonStyle(.plain)
                    .disabled(rows.isEmpty)
                    .accessibilityLabel(subtitleAccessibilityLabel)
                    ForEach(Array(rows.prefix(3).enumerated()), id: \.offset) { entry in
                        let row = entry.element
                        Button {
                            onOpen(row)
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.up.right")
                                    .font(.system(size: 9, weight: .semibold))
                                Text(row.title ?? "Snoozed task")
                                    .font(.system(size: 12))
                                    .multilineTextAlignment(.leading)
                                    .lineLimit(2)
                                    .truncationMode(.tail)
                                Spacer(minLength: 0)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Open \(row.title ?? "snoozed task")")
                    }
                    if state.presentation.remainingCount > 0 {
                        Text("+ \(state.presentation.remainingCount) more")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(overCap ? Color.orange : Color.secondary)
                    }
                }
                Spacer(minLength: 0)
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 22, height: 22)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss wake notice")
            }

            HStack(spacing: 10) {
                Button {
                    if let first = rows.first { onOpen(first) }
                } label: {
                    Label("Open", systemImage: "arrow.up.right")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.bordered)
                .disabled(rows.isEmpty)
                Button(action: onSnooze) {
                    Label("+15m", systemImage: "clock.arrow.circlepath")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.borderedProminent)
                .disabled(state.isSnoozing || rows.isEmpty)
                .accessibilityHint("Snooze every remaining task in this notice")
                if state.isSnoozing {
                    ProgressView().controlSize(.small)
                }
                if let feedback = state.feedback {
                    Text(feedback)
                        .font(.system(size: 11))
                        .foregroundStyle(state.batch.rows.isEmpty ? Color.green : Color.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .lineLimit(2)
                } else {
                    Spacer(minLength: 0)
                    Text("Dismisses in \(Int(ceil(state.secondsRemaining)))s")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .accessibilityLabel(
                            "Dismisses in \(Int(ceil(state.secondsRemaining))) seconds")
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .frame(maxWidth: maximumWidth, alignment: .leading)
        .accessibilityElement(children: .contain)
        .onAppear {
            if !reduceMotion {
                animationTick.toggle()
            }
        }
        .onChange(of: state.batch.wakeID) { _ in
            if !reduceMotion {
                animationTick.toggle()
            }
        }
        .onHover(perform: onHover)
    }

    /// The shared second line: bob's wall-clock time and live-link budget.
    /// The budget portion renders amber when over cap; color supplements
    /// the text rather than carrying the signal alone.
    private var subtitleText: Text {
        let time = state.presentation.wokeTimeText
        let budget = state.presentation.budgetText
        let budgetView = Text(budget)
            .foregroundStyle(overCap ? Color.orange : Color.secondary)
        if rows.count == 1,
            let row = rows.first,
            let receipt = state.batch.receiptTasks.first(where: {
                $0.identityKey == row.identityKey
            }),
            let destination = receipt.destination, !destination.isEmpty
        {
            return Text("woke \(time) · in \(destination) · ")
                .foregroundStyle(.secondary) + budgetView
        }
        return Text("woke \(time) · ").foregroundStyle(.secondary) + budgetView
    }

    private var subtitleAccessibilityLabel: String {
        state.presentation.subtitleText
    }
}

private struct AlarmMotion: ViewModifier {
    let enabled: Bool
    let value: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if enabled {
            content.symbolEffect(.bounce, options: .nonRepeating, value: value)
        } else {
            content
        }
    }
}
