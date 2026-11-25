import CaptureCore
import SwiftUI

let meetingNotesFileButtonID = "org.bobs.bob-mac-capture.meeting-notes-file"
let meetingNotesBackButtonID = "org.bobs.bob-mac-capture.meeting-notes-back"

@available(macOS 26.0, *)
struct MeetingNotesPanelView: View {
    @ObservedObject var model: MeetingNotesPanelModel
    var onOpenNote: (String) -> Void = { _ in }
    @FocusState private var filterIsFocused: Bool

    private var session: MeetingNotesSession? { model.session }

    var body: some View {
        Group {
            if session == nil {
                missingBobView
            } else {
                switch session?.state {
                case .inactive, .loading:
                    loadingView(text: "Loading meeting notes…")
                case .choosingMeeting:
                    choosingMeetingView
                case .choosingParent:
                    choosingParentView
                case .confirmingReplace:
                    confirmingReplaceView
                case .previewReady:
                    previewView
                case .writing:
                    loadingView(text: "Filing meeting notes…")
                case .filed:
                    receiptView(filed: true)
                case .queued:
                    receiptView(filed: false)
                case .empty:
                    emptyView
                case .unsupported:
                    unsupportedView
                case .recoverableError(let code, let message, let hint):
                    errorView(code: code, message: message, hint: hint)
                case .none:
                    loadingView(text: "Loading meeting notes…")
                }
            }
        }
        .frame(minWidth: 480, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear { model.onOpenNote = onOpenNote }
        .onChange(of: model.revision) { _, _ in
            model.onOpenNote = onOpenNote
        }
    }

    private var missingBobView: some View {
        VStack(alignment: .leading, spacing: 12) {
            header(title: "Meeting notes")
            Text(model.missingBob ? "Bob is not available." : "Loading…")
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .background(.regularMaterial)
        .accessibilityLabel("Meeting notes unavailable")
    }

    private func loadingView(text: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            header(title: "Meeting notes")
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(text).foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .background(.regularMaterial)
        .accessibilityLabel(text)
    }

    private func header(title: String) -> some View {
        HStack(spacing: 8) {
            Label(title, systemImage: "person.2.fill")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            Button("Back to Capture", action: model.leave)
                .keyboardShortcut(.cancelAction)
                .accessibilityIdentifier(meetingNotesBackButtonID)
                .accessibilityHint("Returns to the unchanged capture draft.")
        }
    }

    private var choosingMeetingView: some View {
        VStack(alignment: .leading, spacing: 12) {
            header(title: "Choose the meeting")
            if let notice = session?.notice, !notice.isEmpty {
                Text(notice).font(.caption).foregroundStyle(.secondary)
            }
            TextField("Filter meetings", text: $model.filterText)
                .textFieldStyle(.roundedBorder)
                .focused($filterIsFocused)
                .accessibilityLabel("Filter meetings")
            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(model.pickerRows, id: \.id) { row in
                        let meeting = row.meeting
                        Button {
                            model.selectMeeting(meeting)
                        } label: {
                            HStack(spacing: 8) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(meeting.title)
                                        .font(.callout.weight(.medium))
                                    Text("\(meeting.date) · \(meeting.start)–\(meeting.end)")
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if MeetingNotesPresentation.filedRowMark(for: meeting) {
                                    Text("Filed")
                                        .font(.caption2.weight(.medium))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(.quaternary, in: Capsule())
                                        .accessibilityLabel("Already filed")
                                }
                                if meeting.canSelect, meeting.eventRef == model.selectedMeetingRef {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .opacity(meeting.canSelect ? 1 : 0.45)
                        }
                        .buttonStyle(.plain)
                        .disabled(!meeting.canSelect)
                        .accessibilityLabel(
                            meeting.canSelect
                                ? "Select meeting \(meeting.title)"
                                : "Unavailable meeting \(meeting.title)"
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 120, maxHeight: 320)
        }
        .padding(18)
        .background(.regularMaterial)
        .accessibilityLabel("Choose the meeting")
        .onAppear { filterIsFocused = true }
    }

    private var choosingParentView: some View {
        VStack(alignment: .leading, spacing: 12) {
            header(title: "Choose the parent")
            Text("Bob needs a parent for these notes.")
                .font(.callout).foregroundStyle(.secondary)
            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(session?.parentChoices ?? [], id: \.route) { choice in
                        Button {
                            model.chooseParent(choice)
                        } label: {
                            HStack(spacing: 8) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(choice.label).font(.callout.weight(.medium))
                                    Text(choice.route)
                                        .font(.caption.monospaced())
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if choice.route == model.selectedParentRoute {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Choose parent \(choice.label)")
                    }
                }
            }
            .frame(minHeight: 80, maxHeight: 240)
        }
        .padding(18)
        .background(.regularMaterial)
        .accessibilityLabel("Choose the parent")
    }

    private var confirmingReplaceView: some View {
        VStack(alignment: .leading, spacing: 12) {
            header(title: "Meeting notes already filed")
            if let existing = session?.existing {
                Text("Existing note: \(existing.note)")
                    .font(.callout.monospaced())
                    .textSelection(.enabled)
            }
            Text("Choose whether to open the existing note, review a replacement, or keep it.")
                .font(.callout)
            VStack(alignment: .leading, spacing: 8) {
                ForEach(model.replaceActions, id: \.self) { action in
                    Button {
                        model.activateReplaceAction(action)
                    } label: {
                        HStack {
                            Text(action.title)
                            Spacer()
                            if action == model.selectedReplaceAction {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(action.title)
                }
            }
        }
        .padding(18)
        .background(.regularMaterial)
        .accessibilityLabel("Meeting notes already filed")
    }

    private var previewView: some View {
        let response = session?.response
        let meeting = response?.meeting
        let summary = MeetingNotesPresentation.outlineSummary(for: response)
        return VStack(spacing: 0) {
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 10) {
                    header(title: MeetingNotesPresentation.title(for: meeting))
                    Text(MeetingNotesPresentation.dateSpan(for: meeting))
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                    if !MeetingNotesPresentation.destination(for: response).isEmpty {
                        Text(MeetingNotesPresentation.destination(for: response))
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("Destination")
                    }
                    if !MeetingNotesPresentation.effectiveStatus(for: response).isEmpty {
                        Text("Status \(MeetingNotesPresentation.effectiveStatus(for: response))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let match = response?.match, !match.evidence.isEmpty {
                        Text(match.evidence.joined(separator: " · "))
                            .font(.caption).foregroundStyle(.secondary)
                            .accessibilityLabel("Auto-match evidence")
                    }
                    Button("Change meeting") {
                        model.showChooser()
                    }
                    .accessibilityHint("Shows the recent meeting list.")
                    if !summary.tldr.isEmpty {
                        Text(summary.tldr).font(.callout)
                            .accessibilityLabel("Summary")
                    }
                    if !summary.nextSteps.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Next steps").font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            ForEach(Array(summary.nextSteps.enumerated()), id: \.offset) { _, step in
                                Text("• \(step)").font(.callout)
                            }
                        }
                    }
                    if !summary.sections.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Sections (\(summary.sections.count))")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            ForEach(Array(summary.sections.enumerated()), id: \.offset) { _, section in
                                Text(section).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    if let shape = MeetingNotesPresentation.transcriptDisposition(for: response) {
                        Text("Transcript \(shape)").font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(MeetingNotesPresentation.warnings(for: response), id: \.self) { warning in
                        Text(warning).font(.caption).foregroundStyle(.orange)
                    }
                    if let warning = MeetingNotesPresentation.commitWarning(for: response) {
                        Text(warning).font(.caption).foregroundStyle(.orange)
                            .accessibilityLabel("Commit warning")
                    }
                    if let notice = session?.notice, !notice.isEmpty {
                        Text(notice).font(.caption).foregroundStyle(.secondary)
                    }
                    statusControl
                }
                .padding(.horizontal, 18)
                .padding(.top, 18)
                .padding(.bottom, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollBounceBehavior(.basedOnSize)
            footer(canFile: session?.canFile == true)
                .padding(.horizontal, 18)
                .padding(.top, 10)
                .padding(.bottom, 18)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.regularMaterial)
        .accessibilityLabel("Meeting notes preview")
    }

    private var statusControl: some View {
        HStack(spacing: 8) {
            Text("Read as").font(.caption).foregroundStyle(.secondary)
            Picker(
                "Reading status",
                selection: Binding(
                    get: { session?.statusOverride },
                    set: { model.session?.chooseStatus($0) }
                )
            ) {
                Text("Bob default").tag(nil as MeetingNotesStatus?)
                Text("Next").tag(MeetingNotesStatus.next as MeetingNotesStatus?)
                Text("Read").tag(MeetingNotesStatus.read as MeetingNotesStatus?)
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("Reading status")
            Spacer(minLength: 0)
        }
    }

    private func footer(canFile: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Return files this preview. Choices never file.")
                .font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Button("File meeting notes") { model.file() }
                    .disabled(!canFile || session?.isWriting == true)
                    .accessibilityIdentifier(meetingNotesFileButtonID)
                Button("Re-preview") { model.retryPreview() }
                    .disabled(session?.isWriting == true)
                Spacer()
                Button("Back") { model.leave() }
                    .accessibilityIdentifier(meetingNotesBackButtonID)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func receiptView(filed: Bool) -> some View {
        let response = session?.response
        return VStack(alignment: .leading, spacing: 12) {
            header(title: filed ? "Meeting notes filed" : "Meeting notes queued")
            if let queue = response?.queued, !filed {
                Text(queue.detail.isEmpty ? queue.reason : queue.detail)
                    .font(.callout)
                Text("Run bob ref scan to file the queued notes.")
                    .font(.caption).foregroundStyle(.secondary)
                    .accessibilityLabel("Queued next step")
            } else if filed, let filing = response?.filing {
                Text(filing.note).font(.callout.monospaced())
                    .textSelection(.enabled)
                HStack(spacing: 8) {
                    Button("Open note") { model.openExistingOrFiledNote() }
                        .accessibilityLabel("Open filed meeting note")
                    Button("Done") { model.leave() }
                }
            } else {
                Text(filed ? "Filed." : "Queued.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            ForEach(MeetingNotesPresentation.warnings(for: response), id: \.self) { warning in
                Text(warning).font(.caption).foregroundStyle(.orange)
            }
            if let warning = MeetingNotesPresentation.commitWarning(for: response) {
                Text(warning).font(.caption).foregroundStyle(.orange)
                    .accessibilityLabel("Commit warning")
            }
            if let notice = session?.notice, !notice.isEmpty {
                Text(notice).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .background(.regularMaterial)
        .accessibilityLabel(filed ? "Meeting notes filed" : "Meeting notes queued")
    }

    private var emptyView: some View {
        VStack(alignment: .leading, spacing: 12) {
            header(title: "Meeting notes")
            Text(session?.notice ?? "Copy meeting notes, then file them here.")
                .font(.callout).foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Button("Retry preview") { model.retryPreview() }
                Button("Retry list") { model.retryList() }
            }
        }
        .padding(18)
        .background(.regularMaterial)
        .accessibilityLabel("Meeting notes empty")
    }

    private var unsupportedView: some View {
        VStack(alignment: .leading, spacing: 12) {
            header(title: "Meeting notes")
            Label("Meeting notes need a newer bob.", systemImage: "info.circle")
                .foregroundStyle(.secondary)
                .accessibilityLabel("Meeting notes need a newer bob")
            Button("Back to Capture") { model.leave() }
        }
        .padding(18)
        .background(.regularMaterial)
        .accessibilityLabel("Meeting notes unsupported")
    }

    private func errorView(code: String, message: String, hint: String?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            header(title: "Meeting notes")
            Text(message).foregroundStyle(.red).textSelection(.enabled)
            if let hint, !hint.isEmpty {
                Text(hint).font(.caption).foregroundStyle(.secondary)
            }
            Text(code).font(.caption.monospaced()).foregroundStyle(.secondary)
            Button("Retry") { model.retryPreview() }
        }
        .padding(18)
        .background(.regularMaterial)
        .accessibilityLabel("Meeting notes error")
    }
}
