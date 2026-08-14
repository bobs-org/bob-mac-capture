import Foundation

// bob never returns an Obsidian URI, only the absolute filesystem `target` path, so the
// app builds `obsidian://open?path=<percent-encoded target>` itself instead of
// reconstructing a vault-relative link from the typed grammar.
public enum ObsidianOpenURL {
    public static func url(forAbsolutePath path: String) -> URL? {
        guard !path.isEmpty else {
            return nil
        }

        var components = URLComponents()
        components.scheme = "obsidian"
        components.host = "open"
        components.queryItems = [URLQueryItem(name: "path", value: path)]
        return components.url
    }
}
