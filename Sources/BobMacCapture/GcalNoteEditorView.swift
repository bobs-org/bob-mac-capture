import CaptureCore
import SwiftUI

@available(macOS 26.0, *)
struct GcalNoteEditorView: View {
    @ObservedObject var model: GcalNotePanelModel
    let event: GcalNoteEvent

    private var session: GcalNoteSession? { model.session }
    private var live: GcalNotePresentation.LivePreview {
        session?.livePreview
            ?? GcalNotePresentation.LivePreview(
                preview: nil,
                effective: nil,
                spans: [],
                errors: [],
                warnings: [],
                isCurrent: true,
                isPending: false,
                isInvalid: false,
                statusLabel: nil,
                errorMessage: nil
            )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            identityCard
            if event.isRecurring {
                scopeControl
            }
            editorCard
            if let message = live.errorMessage, !message.isEmpty,
                !live.errors.contains(where: { $0.message == message })
            {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
                    .accessibilityLabel("Note validation error")
            }
            ForEach(Array(live.errors.enumerated()), id: \.offset) { _, issue in
                if let message = issue.message, !message.isEmpty {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }
            }
            if !live.warnings.isEmpty {
                ForEach(Array(live.warnings.enumerated()), id: \.offset) { _, warning in
                    Text(warning)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            EventNoteRailView(
                effective: live.effective,
                answer: event.answer
            )
            .opacity(live.isCurrent ? 1 : 0.55)
            landsBlock
            footer
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.regularMaterial)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Event note editor")
    }

    private var identityCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Button("Events", action: model.returnToPicker)
                    .accessibilityHint("Returns to the event list and keeps this draft.")
                Spacer()
                if event.isRecurring {
                    Label("Recurring", systemImage: "repeat")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Text(event.title ?? "Untitled event")
                .font(.title3.weight(.semibold))
                .lineLimit(2)
                .accessibilityAddTraits(.isHeader)
            Text(GcalNotePresentation.identitySubtitle(for: event))
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
            Text(GcalNotePresentation.organizerLabel(for: event))
                .font(.callout)
            if let answer = GcalNotePresentation.answerLabel(event.answer) {
                Text(answer)
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.quaternary, in: Capsule())
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Event identity")
    }

    private var scopeControl: some View {
        HStack(spacing: 8) {
            Picker(
                "Note scope",
                selection: Binding(
                    get: { session?.scope ?? .event },
                    set: { session?.setScope($0) }
                )
            ) {
                Text("This event").tag(GcalNoteScope.event)
                Text("All events").tag(GcalNoteScope.series)
            }
            .pickerStyle(.segmented)
            .disabled(session?.navigationDeferred == true)
            .accessibilityHint("Control-Option-S also toggles this selection.")
            Spacer(minLength: 0)
        }
    }

    private var editorCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            if session?.phase == .writing {
                Label("Saving…", systemImage: "arrow.triangle.2.circlepath")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if let status = live.statusLabel {
                Text(status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            GcalNoteEditorTextView(
                text: session?.editorText ?? "",
                isEditable: session?.phase != .writing,
                matchingSpans: live.isInvalid || live.isCurrent ? live.spans : [],
                matchingErrors: live.errors,
                rootHue: live.effective?.root?.hue ?? event.note?.root?.hue,
                identityKey: identityKey,
                onTextChange: { session?.setEditorText($0) }
            )
            .frame(minHeight: 120, maxHeight: .infinity)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
            )
        }
    }

    private var landsBlock: some View {
        let preview = live.preview
        return VStack(alignment: .leading, spacing: 4) {
            Text("Lands as")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            if let path = preview?.path, !path.isEmpty {
                Text(path)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            Text(GcalNotePresentation.landsExplanation(event: event, preview: preview))
                .font(.callout.monospaced())
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            ForEach(Array((preview?.bullets ?? []).enumerated()), id: \.offset) { _, bullet in
                Text(bullet)
                    .font(.caption.monospaced())
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
        .opacity(0.72)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Lands as")
    }

    private var footer: some View {
        let scope = session?.scope ?? .event
        let recurring = event.isRecurring
        let canUndo = session?.canUndoMutation == true
        let writing = session?.navigationDeferred == true
        return VStack(alignment: .leading, spacing: 8) {
            Text(GcalNotePresentation.footerOwnership(scope: scope))
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(GcalNotePresentation.footerKeys(recurring: recurring, canUndo: canUndo))
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityLabel(
                    GcalNotePresentation.footerKeys(recurring: recurring, canUndo: canUndo)
                )
            HStack(spacing: 8) {
                Button("Save", action: model.save)
                    .disabled(writing)
                Button("Clear", action: model.clear)
                    .disabled(writing || session?.canClearSavedScope != true)
                if canUndo {
                    Button("Undo last save", action: { _ = model.undoLastMutation() })
                        .disabled(writing)
                }
                Spacer()
                Button("Back", action: model.returnToPicker)
                    .disabled(writing)
            }
        }
    }

    private var identityKey: String {
        let identity = event.identity
        let scope = session?.scope.wireValue ?? "event"
        return "\(identity.calendarID)::\(identity.eventID)::\(scope)"
    }
}
