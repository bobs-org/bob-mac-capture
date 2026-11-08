import Foundation

/// Legacy gesture suites exercise other drafts. Exclude the independently tested
/// startup `xx` capability probe when counting their editor rewrite requests.
func nonCloseAliasRewriteCalls(in record: String) -> [Substring] {
    record.split(separator: "\n").filter {
        $0.hasPrefix("argv=capture-rewrite")
            && $0 != "argv=capture-rewrite --cursor 2 --format json -- xx"
    }
}
