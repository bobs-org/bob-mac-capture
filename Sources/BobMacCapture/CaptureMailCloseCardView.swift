import CaptureCore
import SwiftUI

/// The Mail Close card is a presentation of one Bob-reported `mail_close`
/// refusal payload. Every string, row, and digest comes from bob; the Mac
/// renders them verbatim and confirms with `--mail-close <digest>`.
@available(macOS 26.0, *)
struct CaptureMailCloseCard: View {
    let report: CaptureMailCloseReport
    let message: String?
    let onConfirm: () -> Void
    let onOpenGmail: () -> Void
    let onCancel: () -> Void

    private var isWarning: Bool { report.isWarning }

    var body: some View {
        VStack(spacing: 0) {
            header
                .frame(minHeight: 48)
                .padding(.horizontal, 12)
                .padding(.top, 10)
            Divider()
                .padding(.top, 8)
            rows
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            consequence
                .padding(.horizontal, 12)
                .padding(.bottom, 4)
            footer
                .padding(.horizontal, 10)
                .padding(.bottom, 8)
        }
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: CapturePanelLayout.pickerCornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: CapturePanelLayout.pickerCornerRadius)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
        .shadow(radius: 18, y: 8)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Mail Close card, \(report.title), \(report.subtitle)")
        .focusable()
        .focusEffectDisabled()
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "envelope")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(isWarning ? .orange : .secondary)
                .frame(width: 30, height: 30)
                .background(
                    (isWarning ? Color.orange.opacity(0.12) : Color.secondary.opacity(0.12)),
                    in: Circle()
                )
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(report.title)
                    .font(.callout.weight(.semibold))
                    .lineLimit(2)
                    .accessibilityAddTraits(.isHeader)
                Text(report.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .layoutPriority(1)
            Spacer(minLength: 6)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(report.title). \(report.subtitle)")
    }

    private var rows: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(report.tasks.prefix(5).enumerated()), id: \.offset) { _, task in
                VStack(alignment: .leading, spacing: 2) {
                    Text(task.label)
                        .font(.callout)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if let turnLine = task.turnLine, !turnLine.isEmpty {
                        Text(turnLine)
                            .font(.caption)
                            .foregroundStyle(isWarning ? .orange : .secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    if report.tasks.count > 1 {
                        Text(task.path)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
                .padding(.leading, 8)
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(Color.primary.opacity(0.12))
                        .frame(width: 2)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(task.label). \(task.turnLine ?? "")")
            }
            if report.tasks.count > 5 {
                Text("+\(report.tasks.count - 5) more email tasks")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var consequence: some View {
        Text(report.consequence)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel(report.consequence)
    }

    private var footer: some View {
        VStack(spacing: 6) {
            Text(message ?? "Y close · ⌘↩ open in Gmail · esc keep")
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            HStack(spacing: 8) {
                Spacer(minLength: 4)
                if hasGmailURL {
                    Button("Open in Gmail  ⌘↩", action: onOpenGmail)
                        .buttonStyle(CapturePullInActionButtonStyle(prominent: false))
                        .accessibilityLabel("Open the thread in Gmail")
                }
                Button("Keep open", action: onCancel)
                    .buttonStyle(CapturePullInActionButtonStyle(prominent: false))
                    .accessibilityLabel("Keep the email task open")
                Button(action: onConfirm) {
                    HStack(spacing: 4) {
                        Text(confirmLabel)
                        Text("Y").opacity(0.7)
                    }
                }
                .buttonStyle(CapturePullInActionButtonStyle(prominent: true))
                .accessibilityLabel("\(confirmLabel), press Y to confirm")
            }
        }
        .frame(minHeight: 30)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Y closes, Command-Return opens in Gmail, Escape keeps the draft")
    }

    private var hasGmailURL: Bool {
        report.tasks.flatMap(\.mails).contains { !$0.gmailURL.isEmpty }
    }

    private var confirmLabel: String {
        let verb = report.verb.isEmpty ? "Close" : report.verb.capitalized
        return "\(verb) anyway"
    }
}

/// The live-preview banner Slim row shown when a dry run guards an email-task close.
@available(macOS 26.0, *)
struct CaptureMailCloseBanner: View {
    let report: CaptureMailCloseReport

    var body: some View {
        HStack(spacing: 8) {
            Text("✉")
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Closes an email task")
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                if let turnLine = report.tasks.first?.turnLine, !turnLine.isEmpty {
                    Text(turnLine)
                        .font(.caption)
                        .foregroundStyle(report.isWarning ? .orange : .secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 4)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            (report.isWarning ? Color.orange.opacity(0.12) : Color.secondary.opacity(0.10)),
            in: RoundedRectangle(cornerRadius: 8)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Closes an email task. \(report.tasks.first?.turnLine ?? "")")
    }
}
