import Foundation

/// Additive Bob-authored drawer annotation on a preview block line.
/// Carries the verbatim title Bob returns plus its case-folded key,
/// marker provenance, and empty state. Missing or malformed values
/// decode as nil at the containing line, preserving the rest of the
/// capture. Unrecognized marker strings render conservatively.
public struct CaptureDrawerAnnotation: Codable, Hashable, Sendable {
    public let title: String
    public let key: String
    public let marker: CaptureDrawerMarker
    public let empty: Bool

    public init(title: String, key: String, marker: CaptureDrawerMarker, empty: Bool) {
        self.title = title
        self.key = key
        self.marker = marker
        self.empty = empty
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decode(String.self, forKey: .title)
        key = (try? container.decodeIfPresent(String.self, forKey: .key)) ?? title
        let rawMarker = (try? container.decodeIfPresent(String.self, forKey: .marker)) ?? "bold"
        marker = CaptureDrawerMarker(wireValue: rawMarker)
        empty = (try? container.decodeIfPresent(Bool.self, forKey: .empty)) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(title, forKey: .title)
        try container.encode(key, forKey: .key)
        try container.encode(marker.rawValue, forKey: .marker)
        try container.encode(empty, forKey: .empty)
    }

    private enum CodingKeys: String, CodingKey {
        case title
        case key
        case marker
        case empty
    }
}

/// Marker provenance Bob reports for a drawer. Unknown wire values
/// decode as `.unknown` and render conservatively.
public enum CaptureDrawerMarker: String, Codable, Hashable, Sendable {
    case bold
    case legacyCaps = "legacy_caps"
    case section
    case unknown

    public init(wireValue: String?) {
        self = (wireValue.flatMap(CaptureDrawerMarker.init(rawValue:)) ?? .unknown)
    }
}
