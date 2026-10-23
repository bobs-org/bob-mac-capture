import Darwin
import Dispatch
import Foundation
import notify
import RefsCore

/// Observes bob's Darwin `scan-finished` ping, reads the receipt off the
/// main thread, and presents open-PDF updates. Launch never reads a
/// receipt: only events count. Duplicate receipts are dropped by content
/// hash.
@MainActor
final class RefsScanReceiptObserver {
    static let pdfUpdatesThreadIdentifier = "org.bobs.bob-mac-capture.refs-pdf-updates"

    var isPanelVisible: () -> Bool = { false }
    var notificationsEnabled: () -> Bool = { true }
    var isAccessibilityTrusted: () -> Bool = { false }
    var openTabFileNames: () async -> Set<String>? = { nil }
    var onSurface: (RefsPDFUpdates, RefsPDFUpdateSurface) -> Void = { _, _ in }

    private let reader: RefsScanReceiptReader
    private let register: (@escaping @Sendable () -> Void) -> Int32?
    private let cancel: (Int32) -> Void
    private var token: Int32?
    private var lastPresentedHash: UInt64?
    private var notifiedBusyKeys: Set<String> = []

    init(
        reader: RefsScanReceiptReader = RefsScanReceiptReader(),
        register: @escaping (@escaping @Sendable () -> Void) -> Int32? =
            RefsScanReceiptObserver.registerLive,
        cancel: @escaping (Int32) -> Void = { token in _ = notify_cancel(token) }
    ) {
        self.reader = reader
        self.register = register
        self.cancel = cancel
    }

    func start() {
        stop()
        token = register { [weak self] in
            Task { @MainActor in
                await self?.handleEvent()
            }
        }
    }

    func stop() {
        if let token {
            cancel(token)
            self.token = nil
        }
    }

    /// Test seam: process one already-decoded receipt the way a Darwin
    /// event would after the off-main read.
    func processForTests(_ receipt: RefsScanReceipt) async {
        await present(receipt)
    }

    private func handleEvent() async {
        let reader = reader
        let receipt: RefsScanReceipt?
        do {
            receipt = try await Task.detached {
                try reader.read()
            }.value
        } catch {
            return
        }
        guard let receipt else {
            return
        }
        await present(receipt)
    }

    private func present(_ receipt: RefsScanReceipt) async {
        if lastPresentedHash == receipt.contentHash {
            return
        }
        lastPresentedHash = receipt.contentHash

        var openTabs: Set<String>?
        if RefsPDFUpdates.needsOpenTabCheck(receipt.response), isAccessibilityTrusted() {
            openTabs = await openTabFileNames()
        }
        let updates = RefsPDFUpdates(
            response: receipt.response,
            openTabFileNames: openTabs
        )
        let surface = RefsPDFUpdatePresentation.surface(
            for: updates,
            panelVisible: isPanelVisible(),
            notificationsEnabled: notificationsEnabled(),
            previouslyNotifiedBusyKeys: notifiedBusyKeys
        )
        notifiedBusyKeys = surface.nextNotifiedBusyKeys
        onSurface(updates, surface)
    }

    nonisolated private static func registerLive(
        _ handler: @escaping @Sendable () -> Void
    ) -> Int32? {
        var token: Int32 = 0
        let status = notify_register_dispatch(
            RefsScanReceiptReader.darwinNotificationName,
            &token,
            DispatchQueue.global(qos: .utility)
        ) { _ in
            handler()
        }
        return status == 0 ? token : nil
    }
}
