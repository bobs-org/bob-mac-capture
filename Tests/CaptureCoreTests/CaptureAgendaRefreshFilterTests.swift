import XCTest

@testable import CaptureCore

final class CaptureAgendaRefreshFilterTests: XCTestCase {
    private struct Case {
        let name: String
        let paths: [String]
        let flags: VaultChangeFlags
        let expected: Bool

        init(
            name: String,
            paths: [String],
            flags: VaultChangeFlags = [],
            expected: Bool
        ) {
            self.name = name
            self.paths = paths
            self.flags = flags
            self.expected = expected
        }
    }

    func testRelevanceTable() {
        let cases: [Case] = [
            Case(
                name: "visible md note",
                paths: ["/vault/projects/plan.md"],
                flags: [],
                expected: true
            ),
            Case(
                name: "root md note",
                paths: ["/vault/today.md"],
                expected: true
            ),
            Case(
                name: "tasks global filter",
                paths: [
                    "/vault/.obsidian/plugins/obsidian-tasks-plugin/data.json"
                ],
                flags: [],
                expected: true
            ),
            Case(
                name: "must rescan with no paths",
                paths: [],
                flags: [.mustScanSubDirs],
                expected: true
            ),
            Case(
                name: "root changed",
                paths: [],
                flags: [.rootChanged],
                expected: true
            ),
            Case(
                name: "kernel dropped",
                paths: ["/vault/.git/index"],
                flags: [.kernelDropped],
                expected: true
            ),
            Case(
                name: "user dropped",
                paths: [],
                flags: [.userDropped],
                expected: true
            ),
            Case(
                name: "renamed directory",
                paths: ["/vault/ref"],
                flags: [.itemRenamed, .itemIsDir],
                expected: true
            ),
            Case(
                name: "removed directory",
                paths: ["/vault/done/old"],
                flags: [.itemRemoved, .itemIsDir],
                expected: true
            ),
            Case(
                name: "renamed file alone is not enough",
                paths: ["/vault/photo.png"],
                flags: [.itemRenamed],
                expected: false
            ),
            Case(
                name: "git internals ignored",
                paths: ["/vault/.git/index", "/vault/.git/logs/HEAD"],
                flags: [],
                expected: false
            ),
            Case(
                name: "sase state ignored",
                paths: ["/vault/.sase/state.json"],
                flags: [],
                expected: false
            ),
            Case(
                name: "workspace json ignored",
                paths: ["/vault/.obsidian/workspace.json"],
                flags: [],
                expected: false
            ),
            Case(
                name: "hidden md note ignored",
                paths: ["/vault/.trash/deleted.md"],
                flags: [],
                expected: false
            ),
            Case(
                name: "dotfile md note ignored",
                paths: ["/vault/.hidden.md"],
                flags: [],
                expected: false
            ),
            Case(
                name: "pdf ignored",
                paths: ["/vault/notes/paper.pdf"],
                flags: [],
                expected: false
            ),
            Case(
                name: "image ignored",
                paths: ["/vault/assets/photo.png"],
                flags: [],
                expected: false
            ),
            Case(
                name: "path outside the vault ignored",
                paths: ["/other/notes.md"],
                flags: [],
                expected: false
            ),
            Case(
                name: "empty batch",
                paths: [],
                flags: [],
                expected: false
            ),
            Case(
                name: "md wins in a mixed batch",
                paths: ["/vault/.git/index", "/vault/inbox.md"],
                flags: [],
                expected: true
            ),
            Case(
                name: "git directory removal is irrelevant",
                paths: ["/vault/.git/rebase-merge"],
                flags: [.itemRemoved, .itemIsDir],
                expected: false
            ),
            Case(
                name: "visible folder rename is relevant",
                paths: ["/vault/projects/renamed"],
                flags: [.itemRenamed, .itemIsDir],
                expected: true
            ),
        ]
        for testCase in cases {
            let batch = VaultChangeBatch(
                paths: testCase.paths,
                flags: testCase.flags
            )
            XCTAssertEqual(
                CaptureAgendaRefreshFilter.isRelevant(
                    batch,
                    vaultRoot: "/vault"
                ),
                testCase.expected,
                testCase.name
            )
        }
    }

    func testVaultRootWithTrailingSlash() {
        let batch = VaultChangeBatch(paths: ["/vault/inbox.md"])
        XCTAssertTrue(
            CaptureAgendaRefreshFilter.isRelevant(
                batch,
                vaultRoot: "/vault/"
            )
        )
    }
}
