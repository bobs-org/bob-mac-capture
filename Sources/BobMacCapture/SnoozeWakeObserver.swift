import CaptureCore
import Darwin
import Dispatch
import Foundation

/// Observes Bob's Darwin `woken` ping, reads the receipt off-main, and
/// serializes acceptance on MainActor. Overlapping reads coalesce into
/// one follow-up read, and duplicate wake IDs (not byte hashes) are
/// dropped. Launch never fabricates a receipt: `start()` registers and
/// then reads the latest receipt once to recover a missed ping.
///
/// The protocol retains only the latest receipt. This observer is not a
/// durable multi-batch replay queue: distinct batches are queued by the
/// coordinator, and only terminally handled wake IDs persist across
/// restarts, so restarting never silently discards a held latest receipt.
@MainActor
final class SnoozeWakeObserver {
    var onReceipt: (SnoozeWakeReceipt) -> Void = { _ in }
    var onDiagnostic: (String) -> Void = { _ in }

    private let readReceipt: @Sendable () throws -> SnoozeWakeReceipt?
    private let register: (@escaping @Sendable () -> Void) -> Int32?
    private let cancel: (Int32) -> Void
    private var token: Int32?
    private var lastDeliveredWakeID: String?
    private var isReading = false
    private var needsReread = false
    private var generation: UInt64 = 0

    init(
        readReceipt: (@escaping @Sendable () throws -> SnoozeWakeReceipt?)? = nil,
        register: (@escaping (@escaping @Sendable () -> Void) -> Int32?)? = nil,
        cancel: ((Int32) -> Void)? = nil
    ) {
        if let readReceipt {
            self.readReceipt = readReceipt
        } else {
            self.readReceipt = { try SnoozeWakeReceiptReader().read() }
        }
        if let register {
            self.register = register
        } else {
            self.register = Self.registerLive
        }
        if let cancel {
            self.cancel = cancel
        } else {
            self.cancel = { token in _ = notify_cancel(token) }
        }
    }

    /// Registers for the Darwin ping and reads once for a missed ping.
    /// A failed registration leaves desktop fallback available: no
    /// token means no observation, never a fabricated receipt.
    func start() {
        stop()
        generation &+= 1
        token = register { [weak self] in
            Task { @MainActor in
                await self?.handleEvent()
            }
        }
        if token != nil {
            requestRead()
        } else {
            onDiagnostic("snooze wake observer registration failed")
        }
    }

    func stop() {
        generation &+= 1
        isReading = false
        needsReread = false
        if let token {
            cancel(token)
            self.token = nil
        }
    }

    /// Test seam: process one already-decoded receipt the way a Darwin
    /// event would after the off-main read.
    func processForTests(_ receipt: SnoozeWakeReceipt) {
        accept(receipt)
    }

    func resetDeliveredForTests() {
        lastDeliveredWakeID = nil
    }

    private func handleEvent() {
        requestRead()
    }

    private func requestRead() {
        if isReading {
            needsReread = true
            return
        }
        isReading = true
        needsReread = false
        let expectedGeneration = generation
        let readReceipt = readReceipt
        Task.detached {
            let result: Result<SnoozeWakeReceipt?, Error>
            do {
                result = .success(try readReceipt())
            } catch {
                result = .failure(error)
            }
            await MainActor.run { [weak self] in
                self?.finishRead(result, generation: expectedGeneration)
            }
        }
    }

    private func finishRead(
        _ result: Result<SnoozeWakeReceipt?, Error>, generation expected: UInt64
    ) {
        guard expected == generation else {
            return
        }
        isReading = false
        switch result {
        case .success(let receipt):
            if let receipt {
                accept(receipt)
            }
        case .failure(let error):
            onDiagnostic("snooze wake receipt read failed: \(error)")
        }
        if needsReread {
            needsReread = false
            requestRead()
        }
    }

    private func accept(_ receipt: SnoozeWakeReceipt) {
        if let last = lastDeliveredWakeID, last == receipt.wakeID {
            return
        }
        lastDeliveredWakeID = receipt.wakeID
        onReceipt(receipt)
    }

    nonisolated private static func registerLive(
        _ handler: @escaping @Sendable () -> Void
    ) -> Int32? {
        var token: Int32 = 0
        let status = notify_register_dispatch(
            SnoozeWakeReceiptReader.darwinNotificationName,
            &token,
            DispatchQueue.global(qos: .utility)
        ) { _ in
            handler()
        }
        return status == 0 ? token : nil
    }
}
