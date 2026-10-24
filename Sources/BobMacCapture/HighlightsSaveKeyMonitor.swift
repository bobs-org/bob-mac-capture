import AppKit
import CaptureCore
import Foundation
import RefsCore

struct HighlightsSaveKeyEvent: Equatable {
  let charactersIgnoringModifiers: String?
  let command: Bool
  let shift: Bool
  let option: Bool
  let control: Bool
  let isARepeat: Bool

  init(_ event: NSEvent) {
    charactersIgnoringModifiers = event.charactersIgnoringModifiers
    command = event.modifierFlags.contains(.command)
    shift = event.modifierFlags.contains(.shift)
    option = event.modifierFlags.contains(.option)
    control = event.modifierFlags.contains(.control)
    isARepeat = event.isARepeat
  }
}

@MainActor
protocol GlobalKeyMonitorToken: AnyObject {}

@MainActor
protocol GlobalKeyMonitorInstalling: AnyObject {
  func install(
    handler: @escaping (HighlightsSaveKeyEvent) -> Void
  ) -> GlobalKeyMonitorToken?
  func remove(_ token: GlobalKeyMonitorToken)
}

@MainActor
private final class AppKitGlobalKeyMonitorToken: GlobalKeyMonitorToken {
  let eventMonitor: Any

  init(eventMonitor: Any) {
    self.eventMonitor = eventMonitor
  }
}

@MainActor
final class AppKitGlobalKeyMonitorInstaller: GlobalKeyMonitorInstalling {
  func install(
    handler: @escaping (HighlightsSaveKeyEvent) -> Void
  ) -> GlobalKeyMonitorToken? {
    guard let monitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: {
      handler(HighlightsSaveKeyEvent($0))
    }) else {
      return nil
    }
    return AppKitGlobalKeyMonitorToken(eventMonitor: monitor)
  }

  func remove(_ token: GlobalKeyMonitorToken) {
    guard let token = token as? AppKitGlobalKeyMonitorToken else {
      return
    }
    NSEvent.removeMonitor(token.eventMonitor)
  }
}

/// Observes Command-S passively while Highlights is frontmost. The
/// original key event is never consumed, modified, or re-posted.
@MainActor
final class HighlightsSaveKeyMonitor {
  private let notificationCenter: NotificationCenter
  private let installer: GlobalKeyMonitorInstalling
  private let frontmostBundleID: () -> String?
  private let expectedBundleID: () -> String
  private let isTrusted: () -> Bool
  private let isEnabled: () -> Bool
  private let vaultRoot: () -> String
  private let readCurrentDocumentPath: () async -> String?
  private let onScan: () -> Void
  private let now: () -> Date

  private var enabled: Bool
  private var observerTokens: [NSObjectProtocol] = []
  private var monitorToken: GlobalKeyMonitorToken?
  private var scopeReadTask: Task<Void, Never>?
  private var timerTask: Task<Void, Never>?
  private var scopeReadGeneration: UInt64 = 0
  private var scopeReadResolved = false
  private var scopeReadFinished = false
  private var trigger: HighlightsSaveScanTrigger

  var isWaitingToScan: Bool {
    scopeReadResolved && trigger.isArmed
  }

  var didFinishScopeRead: Bool {
    scopeReadFinished
  }

  init(
    notificationCenter: NotificationCenter,
    installer: GlobalKeyMonitorInstalling,
    frontmostBundleID: @escaping () -> String?,
    expectedBundleID: @escaping () -> String,
    isTrusted: @escaping () -> Bool,
    isEnabled: @escaping () -> Bool,
    vaultRoot: @escaping () -> String,
    readCurrentDocumentPath: @escaping () async -> String?,
    now: @escaping () -> Date = { Date() },
    onScan: @escaping () -> Void
  ) {
    self.notificationCenter = notificationCenter
    self.installer = installer
    self.frontmostBundleID = frontmostBundleID
    self.expectedBundleID = expectedBundleID
    self.isTrusted = isTrusted
    self.isEnabled = isEnabled
    self.vaultRoot = vaultRoot
    self.readCurrentDocumentPath = readCurrentDocumentPath
    self.now = now
    self.onScan = onScan
    enabled = isEnabled()
    trigger = HighlightsSaveScanTrigger(vaultRoot: vaultRoot())
  }

  func start() {
    stopObserving()
    let names = [
      NSWorkspace.didActivateApplicationNotification,
      NSWorkspace.didDeactivateApplicationNotification,
      NSWorkspace.didTerminateApplicationNotification,
    ]
    for name in names {
      observerTokens.append(
        notificationCenter.addObserver(
          forName: name,
          object: nil,
          queue: nil
        ) { [weak self] _ in
          Task { @MainActor in self?.sync() }
        }
      )
    }
    sync()
  }

  func stop() {
    stopObserving()
    removeMonitor()
    scopeReadTask?.cancel()
    scopeReadTask = nil
    timerTask?.cancel()
    timerTask = nil
    trigger.disarm()
    scopeReadResolved = false
    scopeReadFinished = false
  }

  func sync(enabled: Bool) {
    self.enabled = enabled
    if !enabled {
      scopeReadTask?.cancel()
      scopeReadTask = nil
      timerTask?.cancel()
      timerTask = nil
      trigger.disarm()
      scopeReadResolved = false
      scopeReadFinished = false
    }
    sync()
  }

  func sync() {
    let shouldInstall = enabled
      && frontmostBundleID() == expectedBundleID()
      && isTrusted()
    if shouldInstall {
      guard monitorToken == nil else { return }
      monitorToken = installer.install { [weak self] event in
        Task { @MainActor in self?.handle(event) }
      }
    } else {
      removeMonitor()
    }
  }

  func libraryChanged(_ batch: VaultChangeBatch) {
    trigger.libraryChanged(batch, at: now())
    scheduleTimerIfScopeResolved()
  }

  /// Drives a due timer with the injected clock. Tests use this after
  /// advancing their clock; the production timer calls the same method.
  func pollNow() {
    timerTask?.cancel()
    timerTask = nil
    guard trigger.poll(at: now()) else {
      scheduleTimerIfScopeResolved()
      return
    }
    scopeReadResolved = false
    CaptureSignpost.event("refs-save-scan-fired")
    onScan()
  }

  private func handle(_ event: HighlightsSaveKeyEvent) {
    guard enabled, isTrusted(),
      HighlightsSaveKey.matches(
        charactersIgnoringModifiers: event.charactersIgnoringModifiers,
        command: event.command,
        shift: event.shift,
        option: event.option,
        control: event.control,
        isARepeat: event.isARepeat
      )
    else {
      return
    }

    if !trigger.isArmed {
      trigger = HighlightsSaveScanTrigger(vaultRoot: vaultRoot())
    }
    trigger.keyPressed(at: now())
    scopeReadResolved = false
    scopeReadFinished = false
    timerTask?.cancel()
    timerTask = nil
    scopeReadTask?.cancel()
    scopeReadGeneration &+= 1
    let generation = scopeReadGeneration
    CaptureSignpost.event("refs-save-scan-armed")
    scopeReadTask = Task { @MainActor [weak self] in
      guard let self else { return }
      let documentPath = await self.readCurrentDocumentPath()
      guard !Task.isCancelled, generation == self.scopeReadGeneration else {
        return
      }
      self.scopeReadFinished = true
      if HighlightsSaveScanScope.isLibraryDocument(
        path: documentPath,
        vaultRoot: self.vaultRoot()
      ) == false {
        self.trigger.disarm()
        self.scopeReadResolved = false
        CaptureSignpost.event("refs-save-scan-skipped")
        return
      }
      // Unknown is deliberately permissive: a scan is harmless when
      // Accessibility could not resolve the selected document.
      self.scopeReadResolved = true
      self.scheduleTimerIfScopeResolved()
    }
  }

  private func scheduleTimerIfScopeResolved() {
    timerTask?.cancel()
    timerTask = nil
    guard scopeReadResolved, let deadline = trigger.nextDeadline else {
      return
    }
    let delay = max(0, deadline.timeIntervalSince(now()))
    let nanoseconds = UInt64(min(delay * 1_000_000_000, Double(UInt64.max)))
    timerTask = Task { @MainActor [weak self] in
      do {
        try await Task.sleep(nanoseconds: nanoseconds)
      } catch {
        return
      }
      guard !Task.isCancelled else { return }
      self?.pollNow()
    }
  }

  private func removeMonitor() {
    guard let monitorToken else { return }
    installer.remove(monitorToken)
    self.monitorToken = nil
  }

  private func stopObserving() {
    for token in observerTokens {
      notificationCenter.removeObserver(token)
    }
    observerTokens.removeAll()
  }
}
