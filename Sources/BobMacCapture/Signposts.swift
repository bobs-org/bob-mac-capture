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

    static func begin(_ name: StaticString) -> IntervalToken {
        IntervalToken(name: name, state: signposter.beginInterval(name))
    }

    static func end(_ token: IntervalToken) {
        signposter.endInterval(token.name, token.state)
    }

    static func measure<T>(_ name: StaticString, operation: () async throws -> T) async rethrows -> T {
        let token = begin(name)
        defer { end(token) }
        return try await operation()
    }
}
