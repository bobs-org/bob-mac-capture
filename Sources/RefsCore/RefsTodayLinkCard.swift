import CaptureCore
import Foundation

public enum RefsTodayLinkPhase: Equatable, Sendable {
  case loading
  case ready
  case refused(message: String, hint: String?)
  case running
  case failed(message: String, hint: String?)
}

public enum RefsTodayLinkCardEffect: Equatable, Sendable {
  case preview(RefsTodayLinkSelector)
  case submit(RefsTodayLinkSelector)
  case reload
  case cancel
  case none
}

/// Snapshot this token when launching an effect, before any debounce or await.
/// Generation prevents an A → B → A selection from accepting the first A's response.
public struct RefsTodayLinkPreviewRequest: Equatable, Sendable {
  public let selector: RefsTodayLinkSelector
  public let generation: UInt64
}

public enum RefsTodayLinkKeyCommand: Equatable, Sendable {
  case submit
  case submitExactName
  case move(Int)
  case cancel
  case ignore
}

public enum RefsTodayLinkKeyMap {
  public static func command(
    keyCode: UInt16, modifiers: RefsCopyKeyModifiers,
    isRunning: Bool, hasMarkedText: Bool = false
  ) -> RefsTodayLinkKeyCommand? {
    // Linking locks the whole field, including ordinary editing shortcuts.
    if isRunning { return .ignore }
    let flags = modifiers.subtracting([.capsLock, .numericPad, .function, .help])
    if keyCode == 48, flags.isEmpty || flags == .shift { return .ignore }
    if hasMarkedText { return nil }
    if keyCode == 36 || keyCode == 76 {
      if flags.isEmpty { return .submit }
      if flags == .shift { return .submitExactName }
    }
    if keyCode == 45, flags == .command { return .submit }
    if keyCode == 53, flags.isEmpty { return .cancel }
    if keyCode == 33, flags == .control { return .cancel }
    if keyCode == 125, flags.isEmpty { return .move(1) }
    if keyCode == 126, flags.isEmpty { return .move(-1) }
    if flags == .control {
      if keyCode == 45 || keyCode == 38 { return .move(1) }
      if keyCode == 35 || keyCode == 40 { return .move(-1) }
    }
    return nil
  }
}

/// Presentation and interaction only. Bob supplies all defaults and validates
/// every selector; this card never computes a destination or authors capture grammar.
public struct RefsTodayLinkCard: Equatable, Sendable {
  public let frozenItemID: String
  public let notePath: String
  public let title: String
  public let kind: RefKind
  public let taskCaption: String
  public private(set) var query = ""
  public private(set) var phase: RefsTodayLinkPhase = .loading
  public private(set) var pomodoros: [RefsTodayLinkPomodoro] = []
  public private(set) var selectedIndex: Int?
  public private(set) var defaultProblem: RefsTodayLinkFailure?
  public private(set) var failure: RefsTodayLinkFailure?
  public private(set) var preview: RefsTodayLinkResponse?
  public private(set) var previewPending = true
  public private(set) var previewRequest: RefsTodayLinkPreviewRequest?
  public private(set) var generation: UInt64 = 0
  private var hasNavigated = false

  public init(item: RefItem) {
    frozenItemID = item.id
    notePath = item.id
    title = item.rawTitle
    kind = item.kind
    taskCaption = RefsTodayLinkPresentation.taskCaption(
      path: item.task?.path, blockID: item.task?.blockID)
    previewRequest = RefsTodayLinkPreviewRequest(selector: .automatic, generation: 0)
  }

  public var visiblePomodoros: [RefsTodayLinkPomodoro] {
    let needle = Self.canonicalName(query).lowercased()
    guard !needle.isEmpty else { return pomodoros }
    let slug = Self.matchSlug(query)
    let tokens = needle.split(separator: " ").map(String.init)
    var tiers = [[RefsTodayLinkPomodoro]](repeating: [], count: 4)
    for row in pomodoros {
      let name = Self.canonicalName(row.name ?? "").lowercased()
      let rowSlug = row.slug ?? Self.matchSlug(name)
      if !name.isEmpty, rowSlug == slug {
        tiers[0].append(row)
      } else if !name.isEmpty, rowSlug.hasPrefix(slug) || name.hasPrefix(needle) {
        tiers[1].append(row)
      } else if !name.isEmpty,
        tokens.allSatisfy({ FuzzyMatcher.match(token: $0, in: FuzzyField(name)) != nil })
      {
        tiers[2].append(row)
      } else if Self.matchesTime(needle, row: row) {
        tiers[3].append(row)
      }
    }
    return tiers.flatMap { $0 }
  }

  public var offersCreate: Bool {
    let slug = Self.matchSlug(query)
    return !Self.canonicalName(query).isEmpty
      && !pomodoros.contains {
        !($0.name ?? "").isEmpty && ($0.slug ?? Self.matchSlug($0.name ?? "")) == slug
      }
  }

  public var rowCount: Int { visiblePomodoros.count + (offersCreate ? 1 : 0) }

  public var selectedPomodoro: RefsTodayLinkPomodoro? {
    guard let selectedIndex, visiblePomodoros.indices.contains(selectedIndex) else { return nil }
    return visiblePomodoros[selectedIndex]
  }

  public var selectsCreate: Bool {
    offersCreate && selectedIndex == visiblePomodoros.count
  }

  public var selector: RefsTodayLinkSelector? {
    if Self.canonicalName(query).isEmpty && !hasNavigated {
      return defaultProblem == nil ? .automatic : nil
    }
    if let row = selectedPomodoro { return .entry(ref: row.ref) }
    return selectsCreate ? .exactName(query) : nil
  }

  /// Apply only the initial listing or the reload requested after a stale write.
  /// A typed query survives the listing and immediately requests its own preview.
  @discardableResult
  public mutating func applyListing(_ response: RefsTodayLinkResponse) -> RefsTodayLinkCardEffect {
    guard phase != .running else { return .none }
    pomodoros = response.pomodoros
    defaultProblem = nil
    failure = nil
    if let problem = response.error {
      if ["multiple_running", "no_open_pomodoro"].contains(problem.code) {
        defaultProblem = problem
      } else {
        failure = problem
        phase = .refused(message: problem.message, hint: problem.hint)
        invalidatePreview()
        return .none
      }
    } else if response.ok != true {
      return refuseInvalidResponse()
    }
    phase = .ready
    resetSelection()
    if selector == .automatic {
      preview = response
      invalidatePreview()
      return .none
    }
    return requestPreview()
  }

  @discardableResult
  public mutating func editQuery(_ value: String) -> RefsTodayLinkCardEffect {
    guard canEdit else { return .none }
    query = value
    clearFailure()
    resetSelection()
    return phase == .loading ? invalidateAndReturnNone() : requestPreview()
  }

  @discardableResult
  public mutating func select(index: Int) -> RefsTodayLinkCardEffect {
    guard canEdit, phase != .loading, (0..<rowCount).contains(index) else { return .none }
    clearFailure()
    selectedIndex = index
    hasNavigated = true
    return requestPreview()
  }

  @discardableResult
  public mutating func handle(_ command: RefsTodayLinkKeyCommand) -> RefsTodayLinkCardEffect {
    guard phase != .running else { return .none }
    switch command {
    case .ignore: return .none
    case .cancel:
      invalidatePreview()
      return .cancel
    case .move(let delta):
      guard canEdit, phase != .loading, rowCount > 0 else { return .none }
      let origin = selectedIndex ?? (delta >= 0 ? -1 : 0)
      return select(index: ((origin + delta) % rowCount + rowCount) % rowCount)
    case .submit, .submitExactName:
      guard canEdit else { return .none }
      let chosen: RefsTodayLinkSelector?
      if phase == .loading {
        guard command == .submit, Self.canonicalName(query).isEmpty else { return .none }
        chosen = .automatic
      } else if command == .submitExactName {
        chosen = Self.canonicalName(query).isEmpty ? nil : .exactName(query)
      } else {
        chosen = selector
      }
      guard let chosen else { return .none }
      phase = .running
      invalidatePreview()
      return .submit(chosen)
    }
  }

  @discardableResult
  public mutating func applyPreview(
    _ response: RefsTodayLinkResponse, for request: RefsTodayLinkPreviewRequest
  ) -> Bool {
    guard phase != .running, previewRequest == request, selector == request.selector else {
      return false
    }
    preview = response
    previewPending = false
    previewRequest = nil
    return true
  }

  /// Listing transport errors use this same envelope-shaped problem.
  @discardableResult
  public mutating func fail(_ problem: RefsTodayLinkFailure) -> RefsTodayLinkCardEffect {
    let wasLoading = phase == .loading
    failure = problem
    phase =
      wasLoading
      ? .refused(message: problem.message, hint: problem.hint)
      : .failed(message: problem.message, hint: problem.hint)
    invalidatePreview()
    return problem.code == "stale_pomodoro" ? .reload : .none
  }

  private var canEdit: Bool {
    if case .refused = phase { return false }
    return phase != .running
  }

  private mutating func clearFailure() {
    if case .failed = phase {
      phase = .ready
      failure = nil
    }
  }

  private mutating func resetSelection() {
    hasNavigated = false
    if Self.canonicalName(query).isEmpty {
      selectedIndex = pomodoros.firstIndex(where: \.isDefault)
    } else {
      selectedIndex = rowCount > 0 ? 0 : nil
    }
  }

  private mutating func requestPreview() -> RefsTodayLinkCardEffect {
    invalidatePreview()
    guard let selector else { return .none }
    previewPending = true
    previewRequest = RefsTodayLinkPreviewRequest(selector: selector, generation: generation)
    return .preview(selector)
  }

  private mutating func invalidatePreview() {
    generation &+= 1
    previewRequest = nil
    previewPending = false
  }

  private mutating func invalidateAndReturnNone() -> RefsTodayLinkCardEffect {
    invalidatePreview()
    return .none
  }

  private mutating func refuseInvalidResponse() -> RefsTodayLinkCardEffect {
    phase = .loading
    return fail(
      RefsTodayLinkFailure(
        code: "invalid_response", message: RefsTodayLinkPresentation.invalidResponse))
  }

  /// Display matching only. Exact-name submissions always carry the untouched query.
  public static func canonicalName(_ text: String) -> String {
    text.split(whereSeparator: \.isWhitespace).joined(separator: " ").uppercased()
  }

  private static func matchSlug(_ text: String) -> String {
    canonicalName(text).lowercased().replacingOccurrences(of: " ", with: "-")
  }

  private static func matchesTime(_ needle: String, row: RefsTodayLinkPomodoro) -> Bool {
    guard let range = row.timeRange else { return false }
    let times = range.split(separator: "-").map(String.init)
    return times.contains { time in
      guard time.count == 4 else { return false }
      let hour = String(time.prefix(2))
      let minute = String(time.suffix(2))
      return [time, "\(hour):\(minute)", "\(Int(hour) ?? 0):\(minute)"].contains(needle)
    }
  }
}
