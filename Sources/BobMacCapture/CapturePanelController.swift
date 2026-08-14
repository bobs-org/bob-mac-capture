import AppKit
import SwiftUI

@MainActor
final class CapturePanelController: NSObject, NSWindowDelegate {
    private let model: CapturePanelModel
    private let keyRouter = CaptureKeyCommandRouter()
    private var panel: NSPanel?
    private var localMonitor: Any?

    init(model: CapturePanelModel) {
        self.model = model
        super.init()
        model.panelDismisser = { [weak self] in self?.hidePanel() }
    }

    deinit {
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }
    }

    func prewarm() {
        _ = makePanelIfNeeded()
    }

    func show() {
        let token = CaptureSignpost.begin("panel-order")
        model.prepareForPresentation()
        let panel = makePanelIfNeeded()
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        installKeyMonitorIfNeeded()
        CaptureSignpost.end(token)
        CaptureSignpost.event("editor-focus-requested")
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        model.requestClose()
    }

    func makePanelIfNeeded() -> NSPanel {
        if let panel {
            return panel
        }

        let created = Self.makePanel()
        created.delegate = self
        created.contentView = NSHostingView(rootView: CapturePanelView(model: model))
        panel = created
        return created
    }

    static func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(
                origin: .zero,
                size: CapturePanelLayout.panelInitialContentSize
            ),
            styleMask: [
                .nonactivatingPanel,
                .titled,
                .fullSizeContentView,
                .resizable,
            ],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.contentMinSize = CapturePanelLayout.panelMinimumContentSize
        return panel
    }

    static func insertNewlineInEditableTextView(
        firstResponder: NSResponder?,
        model: CapturePanelModel
    ) -> Bool {
        guard let textView = firstResponder as? NSTextView,
              textView.isEditable
        else {
            return false
        }

        model.dismissCompletion()
        textView.doCommand(by: #selector(NSResponder.insertNewline(_:)))
        return true
    }

    private func hidePanel() {
        CaptureSignpost.event("panel-dismiss")
        panel?.orderOut(nil)
    }

    private func installKeyMonitorIfNeeded() {
        guard localMonitor == nil else {
            return
        }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self,
                  self.panel?.isKeyWindow == true,
                  let command = self.keyRouter.command(
                    for: event,
                    completionVisible: self.model.completionVisible
                  )
            else {
                return event
            }

            switch command {
            case .submit:
                self.model.submit(openAfterCapture: false)
                return nil
            case .submitAndOpen:
                self.model.submit(openAfterCapture: true)
                return nil
            case .insertNewline:
                if Self.insertNewlineInEditableTextView(
                    firstResponder: self.panel?.firstResponder,
                    model: self.model
                ) {
                    return nil
                }
                return event
            case .escape:
                if self.model.completionVisible {
                    self.model.dismissCompletion()
                    return nil
                }
                if self.model.pendingDiscardConfirmation || !self.model.hasDraft {
                    self.hidePanel()
                } else {
                    _ = self.model.requestClose()
                }
                return nil
            case .acceptCompletion:
                self.model.acceptSelectedCompletion()
                return nil
            case .nextCompletion:
                self.model.selectNextCompletion()
                return nil
            case .previousCompletion:
                self.model.selectPreviousCompletion()
                return nil
            }
        }
    }
}
