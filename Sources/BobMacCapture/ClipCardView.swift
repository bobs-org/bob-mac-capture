import AVFoundation
import AppKit
import CaptureCore
import SwiftUI

/// Hosted Clip card: one `%c` item's clipboard content beneath its preview
/// item. Every string comes from `CaptureClipPresentation`, which itself
/// renders only Bob's `clip` object — kind/count header, Bob's exact child
/// lines, snippet destination, attachment summaries, and entry dividers for
/// `%c<N>` history. `not_read` shows a quiet placeholder. Swift never reads
/// the pasteboard here: image thumbnails and video posters decode from the
/// `source` paths Bob already saved, using Bob's `kind` (never the
/// extension). A missing or unreadable source keeps its summary row.
struct ClipCardView: View {
    let clip: CaptureClipPresentation

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "clipboard")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text(clip.headerText)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            if clip.showsPlaceholder {
                if let placeholder = clip.placeholderText {
                    Text(placeholder)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(Array(clip.topLevelChildLines.enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(.system(.callout, design: .monospaced))
                        .textSelection(.enabled)
                }
                if let destination = clip.snippetDestination {
                    Text("→ \(destination)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                ForEach(Array(clip.attachmentRows.enumerated()), id: \.offset) { _, row in
                    ClipAttachmentRow(row: row)
                }
                ForEach(Array(clip.historyEntries.enumerated()), id: \.offset) { _, entry in
                    ClipHistoryEntryView(entry: entry)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(clip.accessibilitySummary)
    }
}

/// One clipboard file row: the summary Bob reported plus, for images with a
/// readable `source`, a thumbnail, and for videos Bob classified, a
/// cancellable cached poster with a play glyph and duration badge. A missing
/// or unreadable source keeps the summary row so the card stays useful.
struct ClipAttachmentRow: View {
    let row: CaptureClipPresentation.AttachmentRow
    var posterLoader: any VideoPosterLoading = AVFoundationVideoPosterLoader()

    @State private var thumbnail: NSImage?
    @State private var videoPoster: VideoPosterFrame?

    private static let thumbnailPointSize = CGSize(width: 200, height: 120)

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if row.isImage {
                if let thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(
                            maxWidth: Self.thumbnailPointSize.width,
                            maxHeight: Self.thumbnailPointSize.height
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .accessibilityLabel("Clipboard image \(row.savedPath)")
                }
            } else if row.isVideo, let videoPoster {
                videoPosterView(videoPoster)
            }
            Text(row.summaryText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        .task(id: row.source) {
            // Reloads whenever the source changes; a nil result keeps the
            // summary row as the useful fallback.
            if row.isImage {
                thumbnail = Self.loadImage(source: row.source)
                return
            }
            guard row.isVideo else {
                return
            }
            let key = VideoPosterCacheKey(
                source: row.source,
                modificationDate: Self.modificationDate(of: row.source)
            )
            if let cached = VideoPosterMemoryCache.shared.frame(for: key) {
                videoPoster = cached
                return
            }
            let loaded = await posterLoader.load(source: row.source)
            if Task.isCancelled {
                return
            }
            videoPoster = loaded
            if let loaded {
                VideoPosterMemoryCache.shared.store(loaded, for: key)
            }
        }
    }

    @ViewBuilder
    private func videoPosterView(_ poster: VideoPosterFrame) -> some View {
        let badge = CaptureClipPresentation.AttachmentRow.videoDurationBadge(
            seconds: poster.duration)
        ZStack(alignment: .bottomTrailing) {
            Image(nsImage: poster.image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(
                    maxWidth: Self.thumbnailPointSize.width,
                    maxHeight: Self.thumbnailPointSize.height
                )
            Image(systemName: "play.fill")
                .font(.title2)
                .foregroundStyle(.white.opacity(0.9))
                .shadow(radius: 3)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black.opacity(0.28))
            Text(badge)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.white)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(.black.opacity(0.55), in: Capsule())
                .padding(6)
        }
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .accessibilityLabel(row.videoAccessibilityLabel(durationSeconds: poster.duration))
    }

    /// Decodes a thumbnail source off Bob's saved path. Nil for a missing
    /// or unreadable file; callers keep the summary row.
    static func loadImage(source: String) -> NSImage? {
        NSImage(contentsOfFile: source)
    }

    static func modificationDate(of source: String) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: source)[.modificationDate]) as? Date
    }
}

/// In-memory video poster, keyed by Bob's source path and the file's mtime.
struct VideoPosterCacheKey: Hashable, Sendable {
    let source: String
    let modificationDate: Date?
}

struct VideoPosterFrame {
    let image: NSImage
    let duration: TimeInterval
}

protocol VideoPosterLoading {
    func load(source: String) async -> VideoPosterFrame?
}

/// Generates a poster at about 0.1 s via AVFoundation. A missing or
/// undecodable source returns nil so the row keeps its summary.
struct AVFoundationVideoPosterLoader: VideoPosterLoading {
    var thumbnailPointSize: CGSize = CGSize(width: 200, height: 120)

    func load(source: String) async -> VideoPosterFrame? {
        guard FileManager.default.isReadableFile(atPath: source) else {
            return nil
        }
        let asset = AVURLAsset(url: URL(fileURLWithPath: source))
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(
            width: thumbnailPointSize.width * 2,
            height: thumbnailPointSize.height * 2
        )
        generator.requestedTimeToleranceBefore = .positiveInfinity
        generator.requestedTimeToleranceAfter = .positiveInfinity
        let time = CMTime(seconds: 0.1, preferredTimescale: 600)
        do {
            let duration = try await asset.load(.duration)
            if Task.isCancelled {
                return nil
            }
            let (cgImage, _) = try await generator.image(at: time)
            if Task.isCancelled {
                return nil
            }
            let image = NSImage(
                cgImage: cgImage,
                size: NSSize(width: cgImage.width, height: cgImage.height)
            )
            let seconds = CMTimeGetSeconds(duration)
            return VideoPosterFrame(
                image: image,
                duration: seconds.isFinite ? seconds : 0
            )
        } catch {
            return nil
        }
    }
}

final class VideoPosterMemoryCache: @unchecked Sendable {
    static let shared = VideoPosterMemoryCache()

    private let lock = NSLock()
    private var storage: [VideoPosterCacheKey: VideoPosterFrame] = [:]

    func frame(for key: VideoPosterCacheKey) -> VideoPosterFrame? {
        lock.lock()
        defer { lock.unlock() }
        return storage[key]
    }

    func store(_ frame: VideoPosterFrame, for key: VideoPosterCacheKey) {
        lock.lock()
        defer { lock.unlock() }
        storage[key] = frame
    }

    func reset() {
        lock.lock()
        defer { lock.unlock() }
        storage.removeAll()
    }
}

/// One `%c<N>` history entry beneath its divider: the entry's mode, exact
/// lines, snippet destination, and attachments.
private struct ClipHistoryEntryView: View {
    let entry: CaptureClipPresentation.HistoryEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(entry.dividerText) · \(entry.modeText)")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
            ForEach(Array(entry.lines.enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
            }
            if let destination = entry.snippetDestination {
                Text("→ \(destination)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            ForEach(Array(entry.attachmentRows.enumerated()), id: \.offset) { _, row in
                ClipAttachmentRow(row: row)
            }
        }
        .padding(.top, 2)
    }
}
