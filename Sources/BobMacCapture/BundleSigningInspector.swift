import Foundation

enum BundleSigningState: Equatable {
    case unsigned
    case adHoc
    case signed(identity: String)
    case unknown(detail: String)

    var diagnosticText: String {
        switch self {
        case .unsigned:
            return "Unsigned — notification verification requires the installed signed bundle, not swift run"
        case .adHoc:
            return "Ad-hoc signed — notification permissions may not persist across a reinstall with a different identity"
        case .signed(let identity):
            return "Signed: \(identity)"
        case .unknown(let detail):
            return "Signing state unknown: \(detail)"
        }
    }
}

enum BundleSigningInspector {
    // `codesign -dv` writes its human-readable report to stderr even on success.
    static func state(fromCodesignOutput output: String) -> BundleSigningState {
        if output.contains("code object is not signed at all") {
            return .unsigned
        }
        if output.contains("Signature=adhoc") {
            return .adHoc
        }
        if let identity = firstMatch(in: output, prefix: "Authority=") {
            return .signed(identity: identity)
        }
        return .unknown(detail: output.isEmpty ? "no codesign output" : output)
    }

    static func currentBundleState(bundlePath: String = Bundle.main.bundlePath) -> BundleSigningState {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        process.arguments = ["-dv", "--verbose=4", bundlePath]

        let stderrPipe = Pipe()
        process.standardError = stderrPipe
        process.standardOutput = Pipe()

        do {
            try process.run()
        } catch {
            return .unknown(detail: String(describing: error))
        }
        process.waitUntilExit()

        let data = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        return state(fromCodesignOutput: output)
    }

    private static func firstMatch(in text: String, prefix: String) -> String? {
        for line in text.split(separator: "\n") where line.hasPrefix(prefix) {
            return String(line.dropFirst(prefix.count))
        }
        return nil
    }
}
