import Foundation
import os

// Metadata-only instrumentation: signpost names and durations, never captured text.
// `CaptureCore` may only import Foundation, so this lives here rather than alongside
// `BobProcessClient` even though most intervals wrap its calls.
enum CaptureSignpost {
    private static let signposter = OSSignposter(
        subsystem: "org.bobs.bob-mac-capture",
        category: "capture"
    )

    // Wraps `OSSignpostIntervalState` so synchronous call sites (AppKit delegate methods,
    // window lifecycle) don't need their own `import os` just to hold the begin/end token.
    struct IntervalToken {
        fileprivate let name: StaticString
        fileprivate let state: OSSignpostIntervalState
    }

    static func event(_ name: StaticString) {
        signposter.emitEvent(name)
    }

    static func typeAheadHoldEnded(duration: TimeInterval, keyCount: Int) {
        signposter.emitEvent(
            "capture-type-ahead-hold",
            "duration=\(duration, format: .fixed(precision: 3)) keys=\(keyCount)"
        )
    }

    /// Metadata-only snooze event: wake ID, hold or drop reason, task
    /// count, and channel. Never task titles. Empty strings and 0 fill
    /// unused fields so `log show --signpost` always has the same keys.
    static func snooze(
        _ name: StaticString,
        wakeID: String? = nil,
        reason: String? = nil,
        count: Int? = nil,
        channel: String? = nil
    ) {
        let wake = wakeID ?? ""
        let why = reason ?? ""
        let n = count ?? 0
        let ch = channel ?? ""
        signposter.emitEvent(
            name,
            "wake_id=\(wake, privacy: .public) reason=\(why, privacy: .public) count=\(n) channel=\(ch, privacy: .public)"
        )
    }

    static func begin(_ name: StaticString) -> IntervalToken {
        IntervalToken(name: name, state: signposter.beginInterval(name))
    }

    static func end(_ token: IntervalToken) {
        signposter.endInterval(token.name, token.state)
    }

    static func measure<T>(_ name: StaticString, operation: () async throws -> T) async rethrows
        -> T
    {
        let token = begin(name)
        defer { end(token) }
        return try await operation()
    }

    // Idle-agenda intervals and events (plan §10). Metadata only:
    // refresh reasons, counts, and durations, never titles or paths.
    static let agendaRefresh: StaticString = "agenda-refresh"
    static let agendaMeasure: StaticString = "agenda-measure"
    static let agendaPlan: StaticString = "agenda-plan"
    static let agendaUnchanged: StaticString = "agenda-unchanged"
    static let agendaPublished: StaticString = "agenda-published"
    static let agendaHoldReleased: StaticString = "agenda-hold-released"
    static let capturePrepare: StaticString = "capture-prepare"
    static let captureDismiss: StaticString = "capture-dismiss"
    static let templatesRefresh: StaticString = "templates-refresh"
    static let related: StaticString = "capture-related"
    static let relatedUnsupported: StaticString = "capture-related-unsupported"
    static let relatedFailed: StaticString = "capture-related-failed"
    static let relatedPublish: StaticString = "capture-related-publish"
    static let relatedEmpty: StaticString = "capture-related-empty"

    // Snooze wake-notice lifecycle (metadata only: IDs, counts, reasons,
    // never task text). Receipt read, hold/return, verification, presentation,
    // action, and withdrawal each emit one bounded event. Record posts use
    // `snooze-record` so one presentation is one `snooze-present`.
    static let snoozeReceiptRead: StaticString = "snooze-receipt-read"
    static let snoozeHold: StaticString = "snooze-hold"
    static let snoozeReturn: StaticString = "snooze-return"
    static let snoozeVerify: StaticString = "snooze-verify"
    static let snoozePresent: StaticString = "snooze-present"
    static let snoozeRecord: StaticString = "snooze-record"
    static let snoozeAction: StaticString = "snooze-action"
    static let snoozeWithdraw: StaticString = "snooze-withdraw"
}
