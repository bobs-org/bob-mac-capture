import AppKit
import Carbon
import CaptureCore
import ServiceManagement
import XCTest

@testable import BobMacCapture

final class BobMacCaptureTests: XCTestCase {
    @MainActor
    func testPanelHasStableNonActivatingStyleInInitializer() {
        let panel = CapturePanelController.makePanel()

        XCTAssertTrue(panel.styleMask.contains(.nonactivatingPanel))
        XCTAssertTrue(panel.styleMask.contains(.titled))
        XCTAssertTrue(panel.styleMask.contains(.fullSizeContentView))
        XCTAssertTrue(panel.styleMask.contains(.resizable))
        XCTAssertTrue(panel.isFloatingPanel)
        XCTAssertEqual(panel.level, .floating)
        XCTAssertTrue(panel.collectionBehavior.contains(.canJoinAllSpaces))
        XCTAssertTrue(panel.collectionBehavior.contains(.fullScreenAuxiliary))
        XCTAssertEqual(panel.contentMinSize, CapturePanelLayout.panelMinimumContentSize)

        let contentSize = panel.contentRect(forFrameRect: panel.frame).size
        XCTAssertEqual(contentSize, CapturePanelLayout.panelInitialContentSize)
        XCTAssertGreaterThanOrEqual(contentSize.width, panel.contentMinSize.width)
        XCTAssertGreaterThanOrEqual(contentSize.height, panel.contentMinSize.height)
    }

    func testKeyRouterMatchesCaptureShortcuts() {
        let router = CaptureKeyCommandRouter()

        XCTAssertEqual(router.command(for: keyEvent(keyCode: 36)), .submit)
        XCTAssertEqual(router.command(for: keyEvent(keyCode: 36, modifiers: .command)), .submitAndOpen)
        XCTAssertEqual(router.command(for: keyEvent(keyCode: 36, modifiers: .shift)), .insertNewline)
        XCTAssertEqual(router.command(for: keyEvent(keyCode: 36, modifiers: .option)), .insertNewline)
        XCTAssertEqual(router.command(for: keyEvent(keyCode: 38, modifiers: .control)), .insertNewline)
        XCTAssertEqual(router.command(for: keyEvent(keyCode: 53)), .escape)
        XCTAssertEqual(router.command(for: keyEvent(keyCode: 36), completionVisible: true), .acceptCompletion)
        XCTAssertEqual(
            router.command(for: keyEvent(keyCode: 36, modifiers: .command), completionVisible: true),
            .acceptCompletion
        )
        XCTAssertEqual(
            router.command(for: keyEvent(keyCode: 36, modifiers: [.command, .shift])),
            .submitAndOpen
        )
        XCTAssertEqual(
            router.command(for: keyEvent(keyCode: 36, modifiers: [.command, .shift]), completionVisible: true),
            .acceptCompletion
        )
        XCTAssertEqual(
            router.command(for: keyEvent(keyCode: 36, modifiers: .shift), completionVisible: true),
            .insertNewline
        )
        XCTAssertEqual(
            router.command(for: keyEvent(keyCode: 36, modifiers: .option), completionVisible: true),
            .insertNewline
        )
        XCTAssertEqual(
            router.command(for: keyEvent(keyCode: 38, modifiers: .control), completionVisible: true),
            .insertNewline
        )
        XCTAssertNil(router.command(for: keyEvent(keyCode: 38, modifiers: [.control, .shift])))
        XCTAssertEqual(router.command(for: keyEvent(keyCode: 48), completionVisible: true), .acceptCompletion)
        XCTAssertEqual(router.command(for: keyEvent(keyCode: 125), completionVisible: true), .nextCompletion)
        XCTAssertEqual(router.command(for: keyEvent(keyCode: 126), completionVisible: true), .previousCompletion)
        XCTAssertEqual(
            router.command(for: keyEvent(keyCode: 45, modifiers: .control), completionVisible: true),
            .nextCompletion
        )
        XCTAssertEqual(
            router.command(for: keyEvent(keyCode: 35, modifiers: .control), completionVisible: true),
            .previousCompletion
        )
    }

    func testEditorHeightPolicyUsesOneLineMinimumAndSixLineCap() {
        let policy = CaptureEditorHeightPolicy(
            lineHeight: 20,
            verticalPadding: 20,
            maximumVisibleLines: 6,
            displayScale: 2
        )

        let oneLineHeight = policy.resolvedHeight(forMeasuredTextHeight: 0)
        let threeLineHeight = policy.resolvedHeight(forMeasuredTextHeight: 60)
        let sixLineHeight = policy.resolvedHeight(forMeasuredTextHeight: 120)
        let overflowingHeight = policy.resolvedHeight(forMeasuredTextHeight: 180)

        XCTAssertEqual(oneLineHeight, 40)
        XCTAssertEqual(policy.resolvedHeight(forMeasuredTextHeight: 12), oneLineHeight)
        XCTAssertGreaterThan(threeLineHeight, oneLineHeight)
        XCTAssertEqual(threeLineHeight, 80)
        XCTAssertEqual(sixLineHeight, 140)
        XCTAssertEqual(overflowingHeight, sixLineHeight)
        XCTAssertEqual(policy.visibleLineCount(forMeasuredTextHeight: 0), 1)
        XCTAssertEqual(policy.visibleLineCount(forMeasuredTextHeight: 60), 3)
        XCTAssertEqual(policy.visibleLineCount(forMeasuredTextHeight: 180), 6)
    }

    @MainActor
    func testCompletionAcceptanceUsesServerByteReplacementRange() {
        let model = CapturePanelModel()
        model.plainDraft = "idea @ma"
        model.completionResponse = CaptureCompletionResponse(
            ok: true,
            cursor: 8,
            replacement: CaptureRange(start: 6, end: 8),
            context: "route",
            candidates: [
                CaptureCompletionCandidate(
                    replacement: "mac_inbox",
                    route: "mac_inbox",
                    label: "mac_inbox.md",
                    kind: "inbox"
                )
            ]
        )

        model.acceptSelectedCompletion()

        XCTAssertEqual(model.plainDraft, "idea @mac_inbox")
        XCTAssertNil(model.completionResponse)
    }

    @MainActor
    func testInsertNewlineUsesEditableTextViewResponder() {
        let model = CapturePanelModel()
        model.completionResponse = sampleCompletionResponse()

        let textView = NSTextView()
        textView.isEditable = true
        textView.string = "ab"
        textView.setSelectedRange(NSRange(location: 1, length: 0))

        XCTAssertTrue(
            CapturePanelController.insertNewlineInEditableTextView(
                firstResponder: textView,
                model: model
            )
        )
        XCTAssertEqual(textView.string, "a\nb")
        XCTAssertNil(model.completionResponse)
    }

    @MainActor
    func testInsertNewlineDeclinesUnrelatedResponder() {
        let model = CapturePanelModel()
        model.completionResponse = sampleCompletionResponse()

        XCTAssertFalse(
            CapturePanelController.insertNewlineInEditableTextView(
                firstResponder: NSButton(title: "Preview", target: nil, action: nil),
                model: model
            )
        )
        XCTAssertNotNil(model.completionResponse)
    }

    func testHotKeyRegistrationConflictIsReported() {
        let conflictStatus = OSStatus(eventHotKeyExistsErr)
        let registrar = FakeHotKeyRegistrar(status: conflictStatus)
        let manager = HotKeyManager(registrar: registrar) {}

        XCTAssertThrowsError(try manager.register(configuration: .development)) { error in
            XCTAssertEqual(
                error as? HotKeyRegistrationError,
                .registrationFailed(conflictStatus)
            )
        }
    }

    @MainActor
    func testProductionHotkeyIsTheDefaultAndDevelopmentChoicePersists() {
        let suiteName = "org.bobs.bob-mac-capture.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        XCTAssertEqual(AppSettings(defaults: defaults).hotKeyConfiguration, .production)

        defaults.set(false, forKey: "useProductionHotkey")
        XCTAssertEqual(AppSettings(defaults: defaults).hotKeyConfiguration, .development)
        defaults.removePersistentDomain(forName: suiteName)
    }

    func testInfoPlistDeclaresUiElementAndBundleIdentity() throws {
        let plistURL = packageRoot().appendingPathComponent("Resources/Info.plist")
        let data = try Data(contentsOf: plistURL)
        let plist = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        )

        XCTAssertEqual(plist["CFBundleIdentifier"] as? String, "org.bobs.bob-mac-capture")
        XCTAssertEqual(plist["CFBundleDisplayName"] as? String, "Bob Mac Capture")
        XCTAssertEqual(plist["LSUIElement"] as? String, "1")
        XCTAssertEqual(plist["LSMinimumSystemVersion"] as? String, "26.0")
    }

    @MainActor
    func testMainMenuExposesStandardEditSelectorsAndQuit() throws {
        // Regression guard for the AppKit entry-point migration: without an explicit
        // main menu, the capture editor silently loses Cmd-X/C/V/A/Z and the app loses
        // Cmd-Q, since neither the SwiftUI app lifecycle nor a nib supplies one anymore.
        let mainMenu = AppDelegate.makeMainMenu()

        XCTAssertEqual(mainMenu.items.count, 2)

        let editMenu = try XCTUnwrap(mainMenu.items[1].submenu)
        let editSelectors = editMenu.items.map { $0.action.map(NSStringFromSelector) }
        XCTAssertEqual(
            editSelectors,
            ["undo:", "redo:", nil, "cut:", "copy:", "paste:", "selectAll:"]
        )
        XCTAssertEqual(editMenu.items.map(\.keyEquivalent), ["z", "z", "", "x", "c", "v", "a"])
        XCTAssertEqual(editMenu.items[1].keyEquivalentModifierMask, [.command, .shift])

        let appMenu = try XCTUnwrap(mainMenu.items[0].submenu)
        let quitItem = try XCTUnwrap(appMenu.items.last)
        XCTAssertEqual(quitItem.title, "Quit Bob Mac Capture")
        XCTAssertEqual(quitItem.action, #selector(NSApplication.terminate(_:)))
        XCTAssertEqual(quitItem.keyEquivalent, "q")
    }

    @MainActor
    func testStatusMenuOffersRestartBeforeQuit() {
        // Regression guard for the restart flow: Restart must sit directly below the
        // separator and directly above Quit, and every item's action/key-equivalent
        // must match what configureStatusItem() wires up.
        let menu = AppDelegate.makeStatusMenu()

        XCTAssertEqual(
            menu.items.map(\.title),
            ["Capture", "Settings", "Recheck Bob", "", "Restart Bob Mac Capture", "Quit Bob Mac Capture"]
        )
        XCTAssertTrue(menu.items[3].isSeparatorItem)
        XCTAssertEqual(
            menu.items.map { $0.action.map(NSStringFromSelector) },
            ["openCapturePanel", "openSettings", "recheckBob", nil, "restartApp", "quit"]
        )
        XCTAssertEqual(menu.items.map(\.keyEquivalent), ["", ",", "", "", "", "q"])
    }

    @MainActor
    func testOpenSettingsMenuActionUsesRegisteredSettingsPresenterOnce() {
        let delegate = AppDelegate()
        var openSettingsCount = 0
        var activationCount = 0
        delegate.settingsPresentation = SettingsPresentation(
            openSettings: {
                openSettingsCount += 1
            },
            activateApplication: {
                activationCount += 1
            }
        )

        delegate.openSettings()

        XCTAssertEqual(openSettingsCount, 1)
        XCTAssertEqual(activationCount, 1)
    }

    @MainActor
    func testDiagnosticHistoryRecordsChangesAndStaysBounded() {
        let defaults = UserDefaults(suiteName: "org.bobs.bob-mac-capture.tests.\(UUID().uuidString)")!
        let settings = AppSettings(defaults: defaults)

        settings.diagnosticStatus = "Starting"
        XCTAssertTrue(settings.diagnosticHistory.isEmpty, "Setting the same value must not record a duplicate")

        for index in 0..<25 {
            settings.diagnosticStatus = "Status \(index)"
        }

        XCTAssertEqual(settings.diagnosticHistory.count, 20)
        XCTAssertFalse(settings.diagnosticHistory.contains { $0.hasSuffix("Status 0") })
        XCTAssertTrue(settings.diagnosticHistory.contains { $0.hasSuffix("Status 24") })
    }

    func testLaunchAtLoginStateMapping() {
        XCTAssertTrue(LaunchAtLoginState(status: .enabled).enabled)
        XCTAssertFalse(LaunchAtLoginState(status: .notRegistered).enabled)
        XCTAssertFalse(LaunchAtLoginState(status: .requiresApproval).enabled)
        XCTAssertFalse(LaunchAtLoginState(status: .notFound).enabled)
    }

    @MainActor
    private func sampleCompletionResponse() -> CaptureCompletionResponse {
        CaptureCompletionResponse(
            ok: true,
            cursor: 8,
            replacement: CaptureRange(start: 6, end: 8),
            context: "route",
            candidates: [
                CaptureCompletionCandidate(
                    replacement: "mac_inbox",
                    route: "mac_inbox",
                    label: "mac_inbox.md",
                    kind: "inbox"
                )
            ]
        )
    }

    private func keyEvent(keyCode: UInt16, modifiers: NSEvent.ModifierFlags = []) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false,
            keyCode: keyCode
        )!
    }

    private func packageRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}

private final class FakeHotKeyRegistrar: HotKeyRegistering {
    let status: OSStatus

    init(status: OSStatus) {
        self.status = status
    }

    func register(
        configuration: HotKeyConfiguration,
        identifier: EventHotKeyID,
        reference: UnsafeMutablePointer<EventHotKeyRef?>?
    ) -> OSStatus {
        status
    }

    func unregister(reference: EventHotKeyRef) {}
}
