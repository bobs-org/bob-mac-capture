import AppKit
import CaptureCore
import SwiftUI
import XCTest

@testable import BobMacCapture

@MainActor
final class CaptureInboxRouteChoiceDesignTests: XCTestCase {
    func testHeightPolicyUsesDestinationCountAndKeepsEmptyStateReadable() {
        let empty = CaptureInboxRouteChoiceHeightPolicy(rowCount: 0)
        let one = CaptureInboxRouteChoiceHeightPolicy(rowCount: 1)
        let many = CaptureInboxRouteChoiceHeightPolicy(rowCount: 20)

        XCTAssertGreaterThan(empty.minimumVisibleHeight, CapturePanelLayout.inboxRouteBarHeight)
        XCTAssertEqual(one.listViewportHeight, CapturePanelLayout.inboxRouteListPadding * 2
            + CapturePanelLayout.inboxRouteRowHeight)
        XCTAssertEqual(many.listViewportHeight, many.maxListHeight)
        XCTAssertLessThan(many.minimumVisibleHeight, many.idealHeight)
    }

    func testHeightPolicyDoesNotShrinkWhenTheFilterHasNoMatches() {
        let choice = CaptureInboxRouteChoiceState(
            candidates: [candidate()],
            destinations: [destination("health.md"), destination("work.md")]
        )
        let beforeFilter = CaptureInboxRouteChoiceHeightPolicy(choice: choice)
        var filtered = choice
        filtered.filterText = "no destination matches this"
        let afterFilter = CaptureInboxRouteChoiceHeightPolicy(choice: filtered)

        XCTAssertTrue(filtered.filteredDestinations.isEmpty)
        XCTAssertEqual(beforeFilter, afterFilter)
    }

    func testRouterOwnsRouteChoiceKeysAndLeavesFilterTypingNative() {
        let router = CaptureKeyCommandRouter()
        let context = CaptureKeyRoutingContext(inboxRouteChoiceVisible: true, pickerVisible: true)

        XCTAssertEqual(router.command(for: keyEvent(36), context: context), .confirmInboxRouteChoice)
        XCTAssertEqual(
            router.command(for: keyEvent(76, modifiers: .control), context: context),
            .confirmInboxRouteChoiceAndOpen
        )
        XCTAssertEqual(
            router.command(for: keyEvent(36, modifiers: .shift), context: context),
            .keepInboxRouteCandidate
        )
        XCTAssertEqual(router.command(for: keyEvent(53), context: context), .cancelInboxRouteChoice)
        XCTAssertEqual(
            router.command(for: keyEvent(33, modifiers: .control), context: context),
            .cancelInboxRouteChoice
        )
        XCTAssertEqual(
            router.command(for: keyEvent(126), context: context), .previousInboxRouteDestination)
        XCTAssertEqual(
            router.command(for: keyEvent(125), context: context), .nextInboxRouteDestination)
        XCTAssertEqual(
            router.command(for: keyEvent(45, modifiers: .control), context: context),
            .nextInboxRouteDestination
        )
        XCTAssertEqual(
            router.command(for: keyEvent(35, modifiers: .control), context: context),
            .previousInboxRouteDestination
        )
        XCTAssertEqual(
            router.command(for: keyEvent(36, repeat: true), context: context), .consumeKey)
        XCTAssertEqual(router.command(for: keyEvent(17, modifiers: .control), context: context), .consumeKey)
        XCTAssertEqual(router.command(for: keyEvent(42, modifiers: .command), context: context), .consumeKey)
        XCTAssertNil(router.command(for: keyEvent(0), context: context))
        XCTAssertNil(router.command(for: keyEvent(45, modifiers: [.control, .shift]), context: context))
    }

    func testRenderRouteCardAtSupportedWidthsAndAppearances() throws {
        guard #available(macOS 26.0, *) else {
            throw XCTSkip("Inbox route card rendering requires macOS 26.")
        }
        let model = CapturePanelModel()
        model.installInboxRouteChoiceForPreviews(
            route: CaptureInboxRoute(
                supported: true,
                candidateCount: 1,
                candidates: [candidate()],
                destinations: [
                    destination("health.md", label: "Health", kind: "area"),
                    destination("projects/flight-plan.md", label: "Flight plan", kind: "project", status: "wip"),
                    destination("projects/waiting.md", label: "Waiting", kind: "project", status: "waiting", blocked: true),
                ]
            ),
            draft: "@mac_inbox:route-task"
        )
        guard let choice = model.inboxRouteChoice else {
            throw NSError(domain: "CaptureInboxRouteChoiceDesignTests", code: 1)
        }
        let view = VStack(spacing: 12) {
            CaptureInboxRouteChoiceCard(model: model, choice: choice, previewMode: true)
            CaptureInboxRouteChoiceFooter(model: model)
        }
        .padding(18)

        for (name, width) in [
            ("capture-inbox-route-choice-wide", CGFloat(760)),
            ("capture-inbox-route-choice-minimum", CGFloat(CapturePanelLayout.panelMinimumContentWidth)),
        ] {
            try RenderFixtureWriter.write(view, name: name, width: width, appearance: .aqua)
            try RenderFixtureWriter.write(view, name: name, width: width, appearance: .darkAqua)
        }
    }

    private func candidate() -> CaptureInboxRouteCandidate {
        CaptureInboxRouteCandidate(
            key: "mac_inbox.md#^route-task",
            n: 1,
            notePath: "mac_inbox.md",
            inbox: "mac_inbox",
            blockID: "route-task",
            line: 6,
            text: "Plan a weekend walk",
            previousStatusSymbol: " ",
            previousStatusName: "Ready",
            statusSymbol: "*",
            statusName: "Next",
            outcome: "pending"
        )
    }

    private func destination(
        _ path: String,
        label: String = "Health",
        kind: String = "area",
        status: String? = nil,
        blocked: Bool = false
    ) -> CaptureInboxRouteDestination {
        CaptureInboxRouteDestination(
            relativePath: path,
            route: path,
            label: label,
            kind: kind,
            status: status,
            blocked: blocked
        )
    }

    private func keyEvent(
        _ keyCode: UInt16,
        modifiers: NSEvent.ModifierFlags = [],
        repeat isRepeat: Bool = false
    ) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: isRepeat,
            keyCode: keyCode
        )!
    }
}
