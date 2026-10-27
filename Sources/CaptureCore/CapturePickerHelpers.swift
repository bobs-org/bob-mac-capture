import Foundation

/// Shared keyboard and age wording used by pickers in Bob Mac Capture.
/// Keeping these rules in CaptureCore lets portable presentation models and
/// the app's pickers stay in step without depending on each other.
public enum CapturePickerHelpers {
    public static let maximumAcceleratorCount = 36

    private static let acceleratorKeys = Array("1234567890ABC-EFGHIJKLMNOPQRSTUVWXYZ").map(
        String.init)

    public static func accelerator(for index: Int) -> String? {
        guard acceleratorKeys.indices.contains(index) else {
            return nil
        }
        return acceleratorKeys[index]
    }

    public static func acceleratorIndex(for characters: String, entryCount: Int) -> Int? {
        let scalars = Array(characters.unicodeScalars)
        guard scalars.count == 1 else {
            return nil
        }

        let key = String(scalars[0]).uppercased()
        guard let index = acceleratorKeys.firstIndex(of: key),
            index < min(max(entryCount, 0), maximumAcceleratorCount)
        else {
            return nil
        }
        return index
    }

    public static func clampedSelectionIndex(_ index: Int, entryCount: Int) -> Int {
        guard entryCount > 0 else {
            return 0
        }
        return min(max(index, 0), entryCount - 1)
    }

    public static func nextSelectionIndex(after index: Int, entryCount: Int) -> Int {
        guard entryCount > 0 else {
            return 0
        }
        return (clampedSelectionIndex(index, entryCount: entryCount) + 1) % entryCount
    }

    public static func previousSelectionIndex(before index: Int, entryCount: Int) -> Int {
        guard entryCount > 0 else {
            return 0
        }
        return (clampedSelectionIndex(index, entryCount: entryCount) + entryCount - 1) % entryCount
    }

    public static func relativeAgeDescription(from start: Date, to end: Date = Date()) -> String {
        let seconds = max(0, Int(end.timeIntervalSince(start)))
        if seconds < 60 {
            return "just now"
        }
        if seconds < 3_600 {
            return "\(seconds / 60)m ago"
        }
        if seconds < 86_400 {
            return "\(seconds / 3_600)h ago"
        }
        return "\(seconds / 86_400)d ago"
    }

    /// Expanded wording for VoiceOver while retaining the same age buckets as
    /// the compact picker metadata.
    public static func spokenRelativeAgeDescription(from start: Date, to end: Date = Date()) -> String
    {
        let seconds = max(0, Int(end.timeIntervalSince(start)))
        if seconds < 60 {
            return "just now"
        }
        if seconds < 3_600 {
            return countDescription(seconds / 60, unit: "minute") + " ago"
        }
        if seconds < 86_400 {
            return countDescription(seconds / 3_600, unit: "hour") + " ago"
        }
        return countDescription(seconds / 86_400, unit: "day") + " ago"
    }

    private static func countDescription(_ count: Int, unit: String) -> String {
        "\(count) \(unit)\(count == 1 ? "" : "s")"
    }
}
