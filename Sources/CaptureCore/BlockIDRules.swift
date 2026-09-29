import Foundation

/// Bob-driven block-ID character rules for the Block ID Picker.
///
/// Bob is the only authority for the grammar: the app takes the
/// `allowed_character` regex and `allowed_description` wording from the
/// `block_id` object, applies Bob's exact membership (case-sensitive) against
/// Bob's used-ID list, and derives `-2…-99` "next free" variants validated by
/// the same rule. Live preview after insert remains the final authority.
public struct BlockIDRules: Equatable, Sendable {
    /// Bob's human wording, shown verbatim for invalid IDs.
    public let allowedDescription: String
    private let allowed: Set<Character>

    /// Compiles Bob's one-character `allowed_character` class (for example
    /// `[A-Za-z0-9_-]` for `:` or `[A-Za-z0-9-]` for `^`). Returns nil when
    /// the pattern is missing or not a plain character class; nil disables
    /// type-through and New ID rows.
    public init?(allowedCharacter: String, description: String) {
        guard let allowed = Self.parseCharacterClass(allowedCharacter),
              !allowed.isEmpty
        else {
            return nil
        }
        self.allowed = allowed
        self.allowedDescription = description
    }

    /// Whether Bob allows this character in an ID. Only single ASCII scalars
    /// can be allowed; anything multi-scalar is outside Bob's byte grammar.
    public func isAllowed(_ character: Character) -> Bool {
        allowed.contains(character)
    }

    /// Whether the whole string is a committable ID: non-empty with every
    /// character allowed.
    public func isValid(_ id: String) -> Bool {
        guard !id.isEmpty else {
            return false
        }
        return id.allSatisfy(isAllowed)
    }

    /// Type-through split for New ID fields only: when `new` extends `old`
    /// by typing forward and the appended text contains a character outside
    /// Bob's allowed set, returns the committed ID plus the remainder to
    /// insert into the editor after it. Returns nil for mid-field edits
    /// (`new` without `old` as a prefix) and when the appended text is all
    /// allowed. The commit is literal: it applies even when the ID is taken
    /// or invalid, because Bob's preview reports that.
    public func typeThroughSplit(old: String, new: String) -> (id: String, remainder: String)? {
        guard new.hasPrefix(old), new.count > old.count else {
            return nil
        }
        let appended = new.dropFirst(old.count)
        guard let boundary = appended.firstIndex(where: { !isAllowed($0) }) else {
            return nil
        }
        return (
            id: old + String(appended[..<boundary]),
            remainder: String(appended[boundary...])
        )
    }

    /// The first free `-2…-99` variant of `base`, validated by the rule.
    /// Returns nil when `-` is disallowed or no variant is free.
    public func nextFreeVariant(of base: String, used: Set<String>) -> String? {
        guard isAllowed("-") else {
            return nil
        }
        for suffix in 2...99 {
            let candidate = "\(base)-\(suffix)"
            if !used.contains(candidate), isValid(candidate) {
                return candidate
            }
        }
        return nil
    }

    // MARK: - Character-class parsing

    /// Parses a plain `[...]` character class with `A-Z` ranges and literals
    /// (a `-` first or last is literal). Returns nil for anything else, so a
    /// future Bob grammar the app cannot read disables the dependent rows
    /// instead of misvalidating.
    static func parseCharacterClass(_ pattern: String) -> Set<Character>? {
        guard pattern.hasPrefix("["), pattern.hasSuffix("]") else {
            return nil
        }
        let inner = Array(pattern.dropFirst().dropLast())
        guard !inner.isEmpty else {
            return nil
        }
        var allowed: Set<Character> = []
        var index = 0
        while index < inner.count {
            let current = inner[index]
            guard current != "\\" else {
                return nil
            }
            if current == "-",
               index > 0,
               index + 1 < inner.count,
               inner[index + 1] != "]"
            {
                guard let lower = inner[index - 1].asciiValue,
                      let upper = inner[index + 1].asciiValue,
                      lower <= upper
                else {
                    return nil
                }
                for value in UInt32(lower)...UInt32(upper) {
                    if let scalar = Unicode.Scalar(value) {
                        allowed.insert(Character(scalar))
                    }
                }
                index += 2
            } else {
                guard current.isASCII else {
                    return nil
                }
                allowed.insert(current)
                index += 1
            }
        }
        return allowed
    }
}
