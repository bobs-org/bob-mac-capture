import CaptureCore
import SwiftUI

@available(macOS 26.0, *)
struct GcalNotePickerView: View {
    @ObservedObject var model: GcalNotePanelModel
    @FocusState private var filterIsFocused: Bool

    private var session: GcalNoteSession? { model.session }

    var body: some View {
        Group {
            if model.showsEditor, let event = session?.selectedEvent {
                GcalNoteEditorView(model: model, event: event)
            } else {
                pickerChrome
            }
        }
        .frame(minWidth: 480, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var pickerChrome: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Label("Event notes", systemImage: "calendar.badge.note")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button("Back to Capture", action: model.leave)
                    .keyboardShortcut(.cancelAction)
                    .accessibilityHint("Returns to the unchanged capture draft.")
            }

            if let banner = GcalNotePresentation.statusBannerText(
                session?.statusBanner,
                action: session?.writeResponse?.action
            ) {
                Text(banner)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Event note status")
            }

            if let session, !session.ambiguousCandidates.isEmpty {
                Text("Choose the matching event")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            TextField("Filter events", text: Binding(
                get: { session?.filterText ?? "" },
                set: model.setFilter
            ))
            .textFieldStyle(.roundedBorder)
            .focused($filterIsFocused)
            .accessibilityLabel("Filter calendar events")

            pickerContent
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(18)
        .frame(minWidth: 480, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.regularMaterial)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Event note picker")
        .onAppear { filterIsFocused = true }
        .onChange(of: model.showsEditor) { _, showingEditor in
            if !showingEditor {
                filterIsFocused = true
            }
        }
    }

    @ViewBuilder
    private var pickerContent: some View {
        if let session {
            sessionContent(session)
        } else {
            Text(model.missingBob ? "Bob is not available." : "Loading events…")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func sessionContent(_ session: GcalNoteSession) -> some View {
        switch session.phase {
        case .inactive, .loadingList, .resolving, .editing, .previewPending, .writing:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(
                    session.phase == .loadingList || session.phase == .inactive
                        ? "Loading events…" : "Opening event…"
                )
                    .foregroundStyle(.secondary)
            }
        case .listing:
            if model.pickerEvents.isEmpty {
                Text(
                    session.hasNoFilterMatches
                        ? "No events match this filter." : "No events found."
                )
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(session.hasNoFilterMatches
                        ? "No calendar events match the filter"
                        : "No calendar events found")
            } else {
                eventList
            }
        case .unsupported:
            Label("Event notes need a newer bob.", systemImage: "info.circle")
                .foregroundStyle(.secondary)
                .accessibilityLabel("Event notes need a newer bob")
        case .recoverableError(let message, _, _):
            VStack(alignment: .leading, spacing: 8) {
                Text(message)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
                Button("Retry", action: model.retry)
            }
        }
    }

    private var eventList: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(dayGroups, id: \.day) { group in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(dayTitle(group.day))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .padding(.top, 4)
                                .accessibilityAddTraits(.isHeader)
                            ForEach(group.events, id: \.identity) { event in
                                eventRow(event)
                                    .id(event.identity)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollBounceBehavior(.basedOnSize)
            .onChange(of: model.selectedPickerIdentity) { _, identity in
                guard let identity else { return }
                withAnimation(.easeInOut(duration: 0.12)) {
                    proxy.scrollTo(identity, anchor: .center)
                }
            }
            .accessibilityLabel("Calendar events")
        }
    }

    private func eventRow(_ event: GcalNoteEvent) -> some View {
        let selected = event.identity == model.selectedPickerIdentity
        let organizer = event.organizer?.name.flatMap(nonBlank)
            ?? nonBlank(event.calendarName)
            ?? "Calendar"
        let noteSummary = summary(for: event)
        return Button {
            model.open(event)
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Text(event.time ?? "")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 84, alignment: .leading)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(event.title ?? "Untitled event")
                            .font(.callout)
                            .lineLimit(1)
                        if event.isRecurring {
                            Image(systemName: "repeat")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .accessibilityLabel("Recurring")
                        }
                        answerChip(event.answer)
                    }
                    HStack(spacing: 5) {
                        Text(organizer)
                            .lineLimit(1)
                        if let noteSummary {
                            Text("·")
                            Text(noteSummary)
                                .lineLimit(1)
                                .foregroundStyle(rootHue(event.note?.root?.hue))
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                selected ? Color.accentColor.opacity(0.14) : .clear,
                in: RoundedRectangle(cornerRadius: 7)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            accessibilityLabel(for: event, organizer: organizer, noteSummary: noteSummary)
        )
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var dayGroups: [(day: String, events: [GcalNoteEvent])] {
        let grouped = Dictionary(grouping: model.pickerEvents) { $0.day ?? "" }
        return grouped.keys.sorted().map { day in
            (day, grouped[day] ?? [])
        }
    }

    private func dayTitle(_ day: String) -> String {
        let pieces = day.split(separator: "-").compactMap { Int($0) }
        guard pieces.count == 3,
              let date = Calendar.current.date(
                from: DateComponents(year: pieces[0], month: pieces[1], day: pieces[2])
              )
        else {
            return day.isEmpty ? "Date not provided" : day
        }
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInTomorrow(date) { return "Tomorrow" }
        return Self.displayDayFormatter.string(from: date)
    }

    private func summary(for event: GcalNoteEvent) -> String? {
        let note = event.note
        if let text = note?.text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return text.components(separatedBy: .newlines).first
        }
        let lines = note?.lines.filter {
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        } ?? []
        return lines.first
    }

    @ViewBuilder
    private func answerChip(_ answer: String?) -> some View {
        if let label = answerLabel(answer) {
            Text(label)
                .font(.caption2.weight(.medium))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.quaternary, in: Capsule())
        }
    }

    private func answerLabel(_ answer: String?) -> String? {
        switch answer?.lowercased() {
        case "yes", "accepted": "Yes"
        case "maybe", "tentative": "Maybe"
        case "no_reply", "needs_action", "awaiting_reply": "Awaiting reply"
        case "no", "declined": "No"
        default: nil
        }
    }

    private func accessibilityLabel(
        for event: GcalNoteEvent,
        organizer: String,
        noteSummary: String?
    ) -> String {
        var parts = [event.time, event.title, organizer].compactMap { $0 }
        if let answer = answerLabel(event.answer) { parts.append(answer) }
        if event.isRecurring { parts.append("Recurring") }
        if let noteSummary { parts.append("Note: \(noteSummary)") }
        return parts.joined(separator: ", ")
    }

    private func rootHue(_ raw: String?) -> Color {
        switch raw {
        case "blue": .blue
        case "orange": .orange
        case "aqua": .teal
        case "yellow": .yellow
        case "magenta": .pink
        case "green": .green
        case "violet": .purple
        case "red": .red
        default: .secondary
        }
    }

    private func nonBlank(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
            !value.isEmpty
        else {
            return nil
        }
        return value
    }

    private static let displayDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()
}
