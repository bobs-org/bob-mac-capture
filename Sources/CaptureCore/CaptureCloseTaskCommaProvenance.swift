import Foundation

/// Provenance for auto-comma insertions: the UTF-16 locations of `,<digit>`
/// pairs the controller actually applied. The assist decision stays in
/// `CaptureCloseTaskCommaAssist` (Bob's spans authorize insertion); this
/// tracker only remembers where those insertions landed so Backspace can
/// remove exactly its own comma together with its digit.
///
/// All offsets are UTF-16 (`NSString`/`NSRange`) to match `NSTextView`.
/// The pair is always two UTF-16 units (`,` plus ASCII `1`...`9`).
public struct CaptureCloseTaskCommaProvenance: Equatable, Sendable {
    public struct Entry: Equatable, Sendable {
        /// UTF-16 offset of the `,` in the current text.
        public let commaLocation: Int
        /// The digit inserted after the comma (`"1"`...`"9"`).
        public let digit: String

        public init(commaLocation: Int, digit: String) {
            self.commaLocation = commaLocation
            self.digit = digit
        }
    }

    public private(set) var entries: [Entry]

    public init(entries: [Entry] = []) {
        self.entries = entries
    }

    public mutating func clear() {
        entries.removeAll()
    }

    /// Records a newly applied auto-comma insertion. Existing pairs at or
    /// after the insertion shift right by the two inserted units.
    public mutating func record(commaLocation: Int, digit: String) {
        for index in entries.indices where entries[index].commaLocation >= commaLocation {
            let shifted = entries[index].commaLocation + 2
            entries[index] = Entry(commaLocation: shifted, digit: entries[index].digit)
        }
        entries.append(Entry(commaLocation: commaLocation, digit: digit))
    }

    /// Returns the deletion range when the collapsed caret sits immediately
    /// after an intact recorded `,<digit>` pair, else nil. Intact means the
    /// current text still holds exactly `"," + digit` at the recorded spot.
    public func deletionRange(caretLocation: Int, text: String) -> NSRange? {
        let nsText = text as NSString
        for entry in entries where entry.commaLocation + 2 == caretLocation {
            let range = NSRange(location: entry.commaLocation, length: 2)
            guard NSMaxRange(range) <= nsText.length else {
                continue
            }
            if nsText.substring(with: range) == "," + entry.digit {
                return range
            }
        }
        return nil
    }

    /// Consumes the pair under the caret: removes its entry and shifts later
    /// pairs left by the two deleted units. Returns the deleted range, or
    /// nil when no intact recorded pair sits under the caret.
    public mutating func consume(caretLocation: Int, text: String) -> NSRange? {
        guard let range = deletionRange(caretLocation: caretLocation, text: text) else {
            return nil
        }
        entries.removeAll { $0.commaLocation == range.location }
        for index in entries.indices where entries[index].commaLocation > range.location {
            let shifted = entries[index].commaLocation - range.length
            entries[index] = Entry(commaLocation: shifted, digit: entries[index].digit)
        }
        return range
    }

    /// Reconciles ordinary edits: pairs fully before the edit stay, pairs
    /// fully after it shift by the length delta, and pairs touched by the
    /// edit are dropped. Survivors whose text no longer reads `,<digit>`
    /// are also dropped so stale offsets never attach to unrelated text.
    public mutating func reconcile(oldText: String, newText: String) {
        if oldText == newText {
            return
        }
        let oldUnits = Array(oldText.utf16)
        let newUnits = Array(newText.utf16)
        var prefixLength = 0
        while prefixLength < oldUnits.count,
              prefixLength < newUnits.count,
              oldUnits[prefixLength] == newUnits[prefixLength]
        {
            prefixLength += 1
        }
        var suffixLength = 0
        while suffixLength < (oldUnits.count - prefixLength),
              suffixLength < (newUnits.count - prefixLength),
              oldUnits[oldUnits.count - 1 - suffixLength]
                  == newUnits[newUnits.count - 1 - suffixLength]
        {
            suffixLength += 1
        }
        let oldEditLocation = prefixLength
        let oldEditLength = oldUnits.count - prefixLength - suffixLength
        let newEditLength = newUnits.count - prefixLength - suffixLength
        let delta = newEditLength - oldEditLength
        let oldEditMax = oldEditLocation + oldEditLength

        var kept: [Entry] = []
        kept.reserveCapacity(entries.count)
        let nsNew = newText as NSString
        for entry in entries {
            let start = entry.commaLocation
            let end = start + 2
            if end <= oldEditLocation {
                kept.append(entry)
            } else if start >= oldEditMax {
                kept.append(Entry(commaLocation: start + delta, digit: entry.digit))
            } else {
                continue
            }
        }
        entries = kept.filter { entry in
            let range = NSRange(location: entry.commaLocation, length: 2)
            guard range.location >= 0, NSMaxRange(range) <= nsNew.length else {
                return false
            }
            return nsNew.substring(with: range) == "," + entry.digit
        }
    }
}
