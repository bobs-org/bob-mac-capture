import AppKit
import Combine
import Foundation
import XCTest

@testable import BobMacCapture
@testable import RefsCore

/// Inspector tests: the loader cancels on selection changes and
/// caches `ref show` results, the show-failure path keeps the basic
/// column, the ⌘K menu varies with `urls` and `audio`, and copies
/// write the expected pasteboard strings.
@MainActor
final class RefsInspectorLoaderTests: XCTestCase {
  func testLoaderCancelsStaleSelectionLoads() async throws {
    let fixtures = makeFixtures()
    let loader = RefsInspectorLoader(
      library: fixtures.library,
      intrinsics: fixtures.intrinsics
    )

    loader.request(fixtures.chat)
    loader.request(fixtures.paper)
    await waitForContent(loader, id: fixtures.paper.id)

    XCTAssertNil(loader.content(for: fixtures.chat.id))
    XCTAssertNotNil(loader.content(for: fixtures.paper.id))
    XCTAssertEqual(fixtures.fetcher.showPaths, [fixtures.paper.id])
  }

  func testLoaderCachesShowResults() async throws {
    let fixtures = makeFixtures()
    let loader = RefsInspectorLoader(
      library: fixtures.library,
      intrinsics: fixtures.intrinsics
    )

    loader.request(fixtures.paper)
    await waitForContent(loader, id: fixtures.paper.id)
    XCTAssertEqual(fixtures.fetcher.showPaths.count, 1)

    loader.request(fixtures.paper)
    await waitForCalls(fixtures.intrinsics, count: 2)
    XCTAssertEqual(fixtures.fetcher.showPaths.count, 1)
  }

  func testPreviewContentStaysPinnedWhileOtherItemsHydrate() async throws {
    let fixtures = makeFixtures()
    let loader = RefsInspectorLoader(
      library: fixtures.library,
      intrinsics: fixtures.intrinsics
    )
    let installed = RefsInspectorContent(
      summary: RefsSummary(label: "SUMMARY", paragraph: "Pinned preview content")
    )
    loader.installContentForPreviews([fixtures.paper.id: installed])

    loader.request(fixtures.paper)
    try await Task.sleep(nanoseconds: 400_000_000)

    XCTAssertEqual(loader.content(for: fixtures.paper.id), installed)
    XCTAssertTrue(fixtures.fetcher.showPaths.isEmpty)

    loader.request(fixtures.chat)
    await waitForContent(loader, id: fixtures.chat.id)
    XCTAssertEqual(fixtures.fetcher.showPaths, [fixtures.chat.id])
  }

  func testLoaderFeedsSignalsBack() async throws {
    let fixtures = makeFixtures()
    let loader = RefsInspectorLoader(
      library: fixtures.library,
      intrinsics: fixtures.intrinsics
    )

    loader.request(fixtures.paper)
    await waitForContent(loader, id: fixtures.paper.id)

    XCTAssertEqual(
      fixtures.library.signals.pageCounts[fixtures.paper.id],
      22
    )
    XCTAssertEqual(
      fixtures.library.signals.outlineHeadings[fixtures.paper.id],
      ["Method", "Results"]
    )
  }

  func testSummaryExcerptIsKindGated() async throws {
    let fixtures = makeFixtures()
    fixtures.intrinsics.result = RefsPDFIntrinsics(
      pageCount: 22,
      outlineHeadings: ["Method", "Results"],
      leadText: "Bottom line\nShips today.\n\nAbstract\nWe study harness reuse.",
      wordEstimate: 22 * 230,
      thumbnailPNG: nil
    )
    let article = RefItem(
      id: "ref/articles/gated_no_excerpt.md",
      link: "[[ref/articles/gated_no_excerpt]]",
      rawTitle: "Gated Excerpt",
      stem: "gated_no_excerpt",
      kind: .article,
      state: .ready,
      isBlocked: false,
      pdfPath: "lib/articles/gated_no_excerpt.pdf",
      author: "Yangze Liu"
    )
    fixtures.library.installSnapshotForPreviews(
      items: [fixtures.chat, fixtures.paper, article],
      signals: RefsSignals(),
      refreshState: .idle
    )
    let loader = RefsInspectorLoader(
      library: fixtures.library,
      intrinsics: fixtures.intrinsics
    )

    loader.request(fixtures.chat)
    await waitForContent(loader, id: fixtures.chat.id)
    XCTAssertEqual(
      try XCTUnwrap(loader.content(for: fixtures.chat.id)?.summary?.label),
      "SUMMARY"
    )

    loader.request(fixtures.paper)
    await waitForContent(loader, id: fixtures.paper.id)
    XCTAssertEqual(
      try XCTUnwrap(loader.content(for: fixtures.paper.id)?.summary?.label),
      "ABSTRACT"
    )

    loader.request(article)
    await waitForContent(loader, id: article.id)
    XCTAssertNil(loader.content(for: article.id)?.summary)
  }

  func testInspectorContentStaysBounded() async throws {
    let fixtures = makeFixtures()
    fixtures.fetcher.showError = RefsTestError.boom
    fixtures.fetcher.showDelayNanoseconds = 10_000_000
    let loader = RefsInspectorLoader(
      library: fixtures.library,
      intrinsics: fixtures.intrinsics
    )
    for index in 0..<(RefsInspectorLoader.showCacheCapacity + 3) {
      let item = RefItem(
        id: "ref/chat/row-\(index).md",
        link: "[[ref/chat/row-\(index)]]",
        rawTitle: "Row \(index)",
        stem: "row_\(index)",
        kind: .chat,
        state: .ready,
        isBlocked: false,
        pdfPath: "lib/chat/row_\(index).pdf"
      )
      loader.request(item)
      try await Task.sleep(nanoseconds: 150_000_000)
    }
    XCTAssertLessThanOrEqual(
      loader.content.count,
      RefsInspectorLoader.showCacheCapacity
    )
    XCTAssertLessThanOrEqual(
      loader.thumbnails.count,
      RefsInspectorLoader.showCacheCapacity
    )
  }

  func testShowRowRequiresExactPathMatch() async throws {
    let fixtures = makeFixtures()
    fixtures.fetcher.showRowPath = "ref/papers/other.md"
    let loader = RefsInspectorLoader(
      library: fixtures.library,
      intrinsics: fixtures.intrinsics
    )

    let row = await loader.showRow(for: fixtures.paper)
    XCTAssertNil(row)
    XCTAssertNil(loader.cachedShowRow(for: fixtures.paper))

    loader.request(fixtures.paper)
    await waitForContent(loader, id: fixtures.paper.id)
    let content = try XCTUnwrap(loader.content(for: fixtures.paper.id))
    XCTAssertTrue(content.showFailed)
    XCTAssertEqual(content.highlights, [])
  }

  func testShowRowIsSingleFlightForConcurrentCallers() async throws {
    let fixtures = makeFixtures()
    fixtures.fetcher.showDelayNanoseconds = 200_000_000
    let loader = RefsInspectorLoader(
      library: fixtures.library,
      intrinsics: fixtures.intrinsics
    )

    async let first = loader.showRow(for: fixtures.paper)
    async let second = loader.showRow(for: fixtures.paper)
    let (a, b) = await (first, second)

    XCTAssertEqual(a?.path, fixtures.paper.id)
    XCTAssertEqual(a, b)
    XCTAssertEqual(fixtures.fetcher.showPaths, [fixtures.paper.id])
    XCTAssertEqual(loader.cachedShowRow(for: fixtures.paper)?.path, fixtures.paper.id)
  }

  func testCachedShowRowAccessorHitsAfterFetch() async throws {
    let fixtures = makeFixtures()
    let loader = RefsInspectorLoader(
      library: fixtures.library,
      intrinsics: fixtures.intrinsics
    )

    XCTAssertNil(loader.cachedShowRow(for: fixtures.paper))
    let fetchedRow = await loader.showRow(for: fixtures.paper)
    let row = try XCTUnwrap(fetchedRow)
    XCTAssertEqual(loader.cachedShowRow(for: fixtures.paper), row)
    XCTAssertEqual(fixtures.fetcher.showPaths.count, 1)

    let cachedRow = await loader.showRow(for: fixtures.paper)
    let cached = try XCTUnwrap(cachedRow)
    XCTAssertEqual(cached, row)
    XCTAssertEqual(fixtures.fetcher.showPaths.count, 1)
  }

  func testShowFailureKeepsBasicContent() async throws {
    let fixtures = makeFixtures()
    fixtures.fetcher.showError = RefsTestError.boom
    let loader = RefsInspectorLoader(
      library: fixtures.library,
      intrinsics: fixtures.intrinsics
    )

    loader.request(fixtures.paper)
    await waitForContent(loader, id: fixtures.paper.id)

    let content = try XCTUnwrap(loader.content(for: fixtures.paper.id))
    XCTAssertTrue(content.showFailed)
    XCTAssertEqual(content.highlights, [])
    // The basic column still fills: pages and the outline land even
    // when `ref show` fails.
    XCTAssertEqual(content.pageCount, 22)
    XCTAssertEqual(content.outline, ["Method", "Results"])
  }

  func testLoaderHydratesNotesAndHighlightsFromShowFixture() async throws {
    let fixtures = makeFixtures()
    let decoded = try JSONDecoder().decode(
      RefsShowResponse.self,
      from: fixtureData("refs-show-highlights.json")
    )
    let row = try XCTUnwrap(decoded.refs.first)
    fixtures.fetcher.showResponse = RefsShowResponse(
      schemaVersion: 1,
      refs: [
        RefsShowRow(
          path: fixtures.paper.id,
          annotations: row.annotations,
          tasks: row.tasks,
          annotationsStatus: row.annotationsStatus
        )
      ]
    )
    let loader = RefsInspectorLoader(
      library: fixtures.library,
      intrinsics: fixtures.intrinsics
    )

    loader.request(fixtures.paper)
    await waitForContent(loader, id: fixtures.paper.id)
    let content = try XCTUnwrap(loader.content(for: fixtures.paper.id))

    XCTAssertEqual(
      content.highlights.map(\.kind),
      [
        "highlight",
        "highlight",
        "highlight",
        "note",
        "highlight",
        "highlight",
      ]
    )
    XCTAssertEqual(
      content.highlights.map(\.quote),
      [
        "Commented highlights keep their place in Your notes.",
        "Uncommented highlights belong under Highlights.",
        "A whitespace-only comment still counts as uncommented.",
        nil,
        "Same-page highlights share one page label.",
        "The second highlight on this page has no extra label.",
      ]
    )
    XCTAssertEqual(
      content.highlights.filter(\.hasComment).map(\.comment),
      ["Keep this in the notes section."]
    )
    XCTAssertEqual(
      content.highlights.first(where: { $0.kind == "note" })?.comment,
      "A standalone note stays out of the inspector."
    )
    XCTAssertFalse(content.showFailed)
  }

  func testLoaderPublishesImageMetricsWithInspectorEntries() async throws {
    let fixtures = makeFixtures()
    let images = StubAnnotationImages()
    let crop = RefsImageMetrics(pixelWidth: 400, pixelHeight: 200)
    let attached = RefsImageMetrics(pixelWidth: 240, pixelHeight: 80, hasAlpha: true)
    images.metricsByLastComponent = [
      "crop.jpg": crop,
      "note.png": attached,
    ]
    fixtures.fetcher.showDelayNanoseconds = 0
    fixtures.fetcher.showResponse = RefsShowResponse(
      schemaVersion: 1,
      refs: [
        RefsShowRow(
          path: fixtures.paper.id,
          annotations: [
            RefsShowAnnotation(
              pageLabel: "Page 5",
              kind: "image",
              asset: "ref/docs/crop.jpg"
            ),
            RefsShowAnnotation(
              pageLabel: "Page 9",
              kind: "highlight",
              quote: "A quote with a photo.",
              images: ["ref/docs/note.png"]
            ),
            RefsShowAnnotation(
              kind: "note",
              comment: "A standalone thought."
            ),
            RefsShowAnnotation(
              kind: "highlight",
              quote: "Missing crop.",
              images: ["ref/docs/missing.png"]
            ),
            RefsShowAnnotation(
              kind: "highlight",
              quote: "Escapes the vault.",
              images: ["../secret.jpg"]
            ),
          ]
        )
      ]
    )
    let loader = RefsInspectorLoader(
      library: fixtures.library,
      intrinsics: fixtures.intrinsics,
      images: images
    )

    loader.request(fixtures.paper)
    await waitForContent(loader, id: fixtures.paper.id)
    let content = try XCTUnwrap(loader.content(for: fixtures.paper.id))

    XCTAssertEqual(
      content.highlights.map(\.kind),
      ["image", "highlight", "note", "highlight", "highlight"]
    )
    XCTAssertEqual(content.images["ref/docs/crop.jpg"], crop)
    XCTAssertEqual(content.images["ref/docs/note.png"], attached)
    XCTAssertNil(content.images["ref/docs/missing.png"])
    XCTAssertNil(content.images["../secret.jpg"])
    XCTAssertEqual(
      Set(images.metricURLLastComponents),
      ["crop.jpg", "note.png", "missing.png"]
    )
    XCTAssertFalse(
      images.metricURLs.contains(where: { $0.path.contains("secret") })
    )
    XCTAssertEqual(content.feed.hiddenImageCount(visible: 0), 2)
    XCTAssertEqual(
      content.feed.entries(visible: 5)[3].accessibilityLabel,
      "Highlight with note: Missing crop., 1 attached image unavailable"
    )
  }

  func testLoaderWaitsForImageMetricsBeforePublishing() async throws {
    let fixtures = makeFixtures()
    let images = StubAnnotationImages()
    images.metricsDelayNanoseconds = 400_000_000
    images.metricsByLastComponent = [
      "crop.jpg": RefsImageMetrics(pixelWidth: 100, pixelHeight: 40)
    ]
    fixtures.fetcher.showDelayNanoseconds = 0
    fixtures.fetcher.showResponse = RefsShowResponse(
      schemaVersion: 1,
      refs: [
        RefsShowRow(
          path: fixtures.paper.id,
          annotations: [
            RefsShowAnnotation(
              kind: "image",
              asset: "ref/docs/crop.jpg"
            )
          ]
        )
      ]
    )
    let loader = RefsInspectorLoader(
      library: fixtures.library,
      intrinsics: fixtures.intrinsics,
      images: images
    )

    loader.request(fixtures.paper)
    try await Task.sleep(nanoseconds: 250_000_000)
    XCTAssertNil(loader.content(for: fixtures.paper.id))

    await waitForContent(loader, id: fixtures.paper.id)
    let content = try XCTUnwrap(loader.content(for: fixtures.paper.id))
    XCTAssertEqual(
      content.images["ref/docs/crop.jpg"]?.pixelWidth,
      100
    )
  }

  func testImageStoreCachesLoadsAndPreviewImages() async throws {
    let fixtures = makeFixtures()
    let images = StubAnnotationImages()
    let bitmap = makeTestImage(size: NSSize(width: 40, height: 20), color: .systemTeal)
    images.imageByLastComponent = ["crop.jpg": bitmap]
    let store = RefsInspectorImageStore(
      library: fixtures.library,
      provider: images
    )

    XCTAssertNil(store.cachedImage(path: "ref/docs/crop.jpg", maxPixel: 80))
    let loaded = await store.loadImage(path: "ref/docs/crop.jpg", maxPixel: 80)
    XCTAssertEqual(loaded?.size, bitmap.size)
    XCTAssertNotNil(store.cachedImage(path: "ref/docs/crop.jpg", maxPixel: 80))
    XCTAssertEqual(images.imageURLs.count, 1)
    _ = await store.loadImage(path: "ref/docs/crop.jpg", maxPixel: 80)
    XCTAssertEqual(images.imageURLs.count, 1)

    let preview = makeTestImage(size: NSSize(width: 12, height: 8), color: .systemOrange)
    store.installImagesForPreviews(["ref/docs/any.jpg": preview])
    XCTAssertEqual(
      store.cachedImage(path: "ref/docs/any.jpg", maxPixel: 1)?.size,
      preview.size
    )
    XCTAssertEqual(
      store.cachedImage(path: "ref/docs/any.jpg", maxPixel: 4096)?.size,
      preview.size
    )
  }

  func testDecodedImageBudgetEvictsLeastRecentToStayWithinLimit() {
    let budget = RefsDecodedImageBudget(byteLimit: 100)
    let first = makeTestImage(size: NSSize(width: 10, height: 10), color: .systemRed)
    let second = makeTestImage(size: NSSize(width: 12, height: 8), color: .systemBlue)
    let keyA = RefsDecodedImageKey(
      vaultRoot: "/vault",
      path: "a.jpg",
      fileVersion: "1:1",
      maxPixel: 20
    )
    let keyB = RefsDecodedImageKey(
      vaultRoot: "/vault",
      path: "b.jpg",
      fileVersion: "1:1",
      maxPixel: 20
    )
    budget.insert(first, cost: 80, for: keyA)
    budget.insert(second, cost: 80, for: keyB)
    XCTAssertNil(budget.image(for: keyA))
    XCTAssertNotNil(budget.image(for: keyB))
    XCTAssertEqual(budget.count, 1)
    XCTAssertEqual(budget.byteCost, 80)
  }

  func testImageStoreReloadsWhenTheFileChanges() async throws {
    let fixtures = makeFixtures()
    let vault = fixtures.library.vaultRootURL
    let relative = "ref/docs/crop.jpg"
    let url = vault.appendingPathComponent(relative)
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    defer { try? FileManager.default.removeItem(at: vault) }
    let first = makeTestImage(size: NSSize(width: 40, height: 20), color: .systemTeal)
    let second = makeTestImage(size: NSSize(width: 80, height: 40), color: .systemOrange)
    try writePNG(first, to: url)
    try FileManager.default.setAttributes(
      [.modificationDate: Date(timeIntervalSince1970: 1_700_000_000)],
      ofItemAtPath: url.path
    )
    let images = StubAnnotationImages()
    images.imageByLastComponent = ["crop.jpg": first]
    let store = RefsInspectorImageStore(
      library: fixtures.library,
      provider: images
    )

    let loadedFirst = await store.loadImage(path: relative, maxPixel: 80)
    XCTAssertEqual(loadedFirst?.size, first.size)
    XCTAssertEqual(images.imageURLCount, 1)

    try writePNG(second, to: url)
    try FileManager.default.setAttributes(
      [.modificationDate: Date(timeIntervalSince1970: 1_700_000_002)],
      ofItemAtPath: url.path
    )
    images.imageByLastComponent = ["crop.jpg": second]
    let loadedSecond = await store.loadImage(path: relative, maxPixel: 80)
    XCTAssertEqual(loadedSecond?.size, second.size)
    XCTAssertEqual(images.imageURLCount, 2)
    XCTAssertEqual(
      store.cachedImage(path: relative, maxPixel: 80)?.size,
      second.size
    )
  }

  func testImageStoreResetDropsOutstandingLoads() async throws {
    let fixtures = makeFixtures()
    let images = StubAnnotationImages()
    let bitmap = makeTestImage(size: NSSize(width: 40, height: 20), color: .systemTeal)
    images.imageByLastComponent = ["crop.jpg": bitmap]
    images.beginHoldingImages()
    let store = RefsInspectorImageStore(
      library: fixtures.library,
      provider: images
    )
    defer { images.releaseHeldImages() }

    let pending = Task {
      await store.loadImage(path: "ref/docs/crop.jpg", maxPixel: 80)
    }
    let requested = await waitUntil(timeout: 1.5) { images.imageURLCount == 1 }
    XCTAssertTrue(requested)
    store.reset()
    images.releaseHeldImages()
    let result = await pending.value
    XCTAssertNil(result)
    XCTAssertNil(store.cachedImage(path: "ref/docs/crop.jpg", maxPixel: 80))
  }

  func testImageStoreCoalescesInFlightLoads() async throws {
    let fixtures = makeFixtures()
    let images = StubAnnotationImages()
    let bitmap = makeTestImage(size: NSSize(width: 40, height: 20), color: .systemTeal)
    images.imageByLastComponent = ["crop.jpg": bitmap]
    images.beginHoldingImages()
    let store = RefsInspectorImageStore(
      library: fixtures.library,
      provider: images
    )
    defer { images.releaseHeldImages() }

    async let first = store.loadImage(path: "ref/docs/crop.jpg", maxPixel: 80)
    async let second = store.loadImage(path: "ref/docs/crop.jpg", maxPixel: 80)
    let requested = await waitUntil(timeout: 1.5) { images.imageURLCount == 1 }
    XCTAssertTrue(requested)
    images.releaseHeldImages()
    let (left, right) = await (first, second)
    XCTAssertEqual(left?.size, bitmap.size)
    XCTAssertEqual(right?.size, bitmap.size)
    XCTAssertEqual(images.imageURLCount, 1)
  }

  func testImageStoreBudgetBoundsRetention() async throws {
    let fixtures = makeFixtures()
    let images = StubAnnotationImages()
    let first = makeTestImage(size: NSSize(width: 40, height: 20), color: .systemTeal)
    let second = makeTestImage(size: NSSize(width: 30, height: 16), color: .systemOrange)
    images.imageByLastComponent = [
      "crop.jpg": first,
      "note.png": second,
    ]
    let budget = RefsDecodedImageBudget(
      byteLimit: RefsDecodedImageBudget.byteCost(for: first)
    )
    let store = RefsInspectorImageStore(
      library: fixtures.library,
      provider: images,
      budget: budget
    )

    _ = await store.loadImage(path: "ref/docs/crop.jpg", maxPixel: 80)
    XCTAssertNotNil(store.cachedImage(path: "ref/docs/crop.jpg", maxPixel: 80))
    _ = await store.loadImage(path: "ref/docs/note.png", maxPixel: 80)
    XCTAssertNil(store.cachedImage(path: "ref/docs/crop.jpg", maxPixel: 80))
    XCTAssertNotNil(store.cachedImage(path: "ref/docs/note.png", maxPixel: 80))
    XCTAssertEqual(budget.count, 1)
  }

  func testAnnotationImageLoaderReadsRasterPng() async throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let url = root.appendingPathComponent("sample.png")
    let source = makeTestImage(
      size: NSSize(width: 64, height: 32),
      color: .systemRed
    )
    let tiff = try XCTUnwrap(source.tiffRepresentation)
    let rep = try XCTUnwrap(NSBitmapImageRep(data: tiff))
    let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
    try png.write(to: url)

    let loader = RefsAnnotationImageLoader()
    let loadedMetrics = await loader.metrics(for: url)
    let metrics = try XCTUnwrap(loadedMetrics)
    XCTAssertEqual(metrics.pixelWidth, 64)
    XCTAssertEqual(metrics.pixelHeight, 32)
    let loadedThumbnail = await loader.image(for: url, maxPixel: 16)
    let thumbnail = try XCTUnwrap(loadedThumbnail)
    XCTAssertLessThanOrEqual(
      max(thumbnail.size.width, thumbnail.size.height),
      16
    )
  }

  func testAnnotationImageLoaderReadsSvgOnMainActor() async throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let url = root.appendingPathComponent("mark.svg")
    let svg = """
      <svg xmlns="http://www.w3.org/2000/svg" width="80" height="40">
        <rect width="80" height="40" fill="#f00"/>
      </svg>
      """
    try Data(svg.utf8).write(to: url)

    let loader = RefsAnnotationImageLoader()
    let loadedMetrics = await loader.metrics(for: url)
    let metrics = try XCTUnwrap(loadedMetrics)
    XCTAssertEqual(metrics.pixelWidth, 80)
    XCTAssertEqual(metrics.pixelHeight, 40)
    XCTAssertTrue(metrics.hasAlpha)
    let loadedImage = await loader.image(for: url, maxPixel: 16)
    let image = try XCTUnwrap(loadedImage)
    XCTAssertGreaterThan(image.size.width, 0)
  }

  func testImageStoreRejectsEscapingPaths() async throws {
    let fixtures = makeFixtures()
    let images = StubAnnotationImages()
    let store = RefsInspectorImageStore(
      library: fixtures.library,
      provider: images
    )
    let loaded = await store.loadImage(path: "../secret.jpg", maxPixel: 80)
    XCTAssertNil(loaded)
    XCTAssertTrue(images.imageURLs.isEmpty)
  }

  func testShowFailureLeavesHighlightsEmpty() async throws {
    let fixtures = makeFixtures()
    fixtures.fetcher.showError = RefsTestError.boom
    let loader = RefsInspectorLoader(
      library: fixtures.library,
      intrinsics: fixtures.intrinsics
    )

    loader.request(fixtures.paper)
    await waitForContent(loader, id: fixtures.paper.id)
    let content = try XCTUnwrap(loader.content(for: fixtures.paper.id))

    XCTAssertTrue(content.showFailed)
    XCTAssertEqual(content.highlights, [])
  }

  func testRevealMoreWithOnlyHighlightsEmitsRange() throws {
    let model = makePreviewModel()
    let item = previewChat()
    let highlights = (1...8).map { index in
      RefsShowAnnotation(
        pageLabel: "\(index)",
        kind: "highlight",
        quote: "Quote \(index)",
        comment: (index == 2 || index == 4) ? "Note \(index)" : nil
      )
    }
    model.installForPreviews(
      items: [item],
      signals: RefsSignals(),
      query: "",
      scope: .all,
      selectedID: item.id,
      banner: nil,
      refreshState: .idle,
      inspector: [item.id: RefsInspectorContent(highlights: highlights)]
    )
    var received: [RefsInspectorNotesReveal] = []
    let cancellable = model.inspectorNoteReveals.sink {
      received.append($0)
    }

    XCTAssertTrue(model.revealMoreInspectorNotes())
    XCTAssertEqual(received.count, 1)
    let reveal = try XCTUnwrap(received.first)
    XCTAssertEqual(reveal.range, 5..<8)
    XCTAssertEqual(reveal.id, item.id)
    _ = cancellable
  }

  func testRevealMoreWhenFeedFitsThePageReturnsFalse() {
    let model = makePreviewModel()
    let item = previewChat()
    model.installForPreviews(
      items: [item],
      signals: RefsSignals(),
      query: "",
      scope: .all,
      selectedID: item.id,
      banner: nil,
      refreshState: .idle,
      inspector: [
        item.id: RefsInspectorContent(
          highlights: [
            RefsShowAnnotation(
              pageLabel: "1",
              kind: "highlight",
              quote: "One",
              comment: "Note one"
            ),
            RefsShowAnnotation(
              pageLabel: "2",
              kind: "highlight",
              quote: "Two",
              comment: "Note two"
            ),
            RefsShowAnnotation(
              pageLabel: "3",
              kind: "highlight",
              quote: "Three"
            ),
          ]
        )
      ]
    )

    XCTAssertFalse(model.revealMoreInspectorNotes())
  }

  func testSlowIntrinsicsReadTimesOutNearThreeSeconds() async throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString)
    let slow = await RefsPDFIntrinsicsLoader(
      cacheDirectory: root,
      reader: { @Sendable _ in
        try? await Task.sleep(nanoseconds: 10_000_000_000)
        return RefsPDFIntrinsics(pageCount: 9)
      }
    )
    let missing = root.appendingPathComponent("no-such.pdf")
    let start = Date()
    let timedOut = await slow.intrinsics(for: missing, id: "slow")
    let elapsed = Date().timeIntervalSince(start)
    XCTAssertTrue(timedOut.failed)
    XCTAssertNil(timedOut.pageCount)
    XCTAssertGreaterThanOrEqual(elapsed, 2.5)
    XCTAssertLessThan(elapsed, 9)

    // The abandoned read never queues later loads behind it: a
    // fresh loader answers at once.
    let fast = await RefsPDFIntrinsicsLoader(
      cacheDirectory: root,
      reader: { @Sendable _ in RefsPDFIntrinsics(pageCount: 3) }
    )
    let restart = Date()
    let second = await fast.intrinsics(for: missing, id: "fast")
    XCTAssertEqual(second.pageCount, 3)
    XCTAssertLessThan(Date().timeIntervalSince(restart), 2)
  }

  func testIntrinsicsCacheLocksFilesDown() async throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString)
    let loader = await RefsPDFIntrinsicsLoader(
      cacheDirectory: root,
      reader: { @Sendable _ in
        RefsPDFIntrinsics(
          pageCount: 5,
          thumbnailPNG: Data([0x89, 0x50, 0x4E, 0x47])
        )
      }
    )
    try FileManager.default.createDirectory(
      at: root, withIntermediateDirectories: true
    )
    let pdf = root.appendingPathComponent("note.pdf")
    FileManager.default.createFile(
      atPath: pdf.path, contents: Data("fake".utf8)
    )
    let loaded = await loader.intrinsics(for: pdf, id: "mode-check")
    XCTAssertEqual(loaded.pageCount, 5)

    func permissions(of url: URL) throws -> Int {
      let attributes = try FileManager.default.attributesOfItem(
        atPath: url.path
      )
      return (attributes[.posixPermissions] as? NSNumber)?.intValue ?? 0
    }
    XCTAssertEqual(try permissions(of: root), 0o700)
    XCTAssertEqual(
      try permissions(of: root.appendingPathComponent("thumbs-v2")), 0o700
    )
    XCTAssertEqual(
      try permissions(of: root.appendingPathComponent("intrinsics-v2.json")),
      0o600
    )
    let thumbs = try FileManager.default.contentsOfDirectory(
      at: root.appendingPathComponent("thumbs-v2"),
      includingPropertiesForKeys: nil
    )
    XCTAssertEqual(thumbs.count, 1)
    XCTAssertEqual(try permissions(of: XCTUnwrap(thumbs.first)), 0o600)
  }

  func testThumbnailSizeMatchesWideLayout() {
    // Both inspector layouts draw from the one 300 x 388 px image
    // (150 x 194 pt at 2x); compact downsamples it to 112 x 145.
    XCTAssertEqual(
      RefsPDFIntrinsicsLoader.thumbnailSize,
      CGSize(width: 300, height: 388)
    )
  }

  func testIntrinsicsRemovesLegacyCacheOnSetup() async throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString)
    // Pre-seed the legacy v1 files: stale 224 x 290 thumbnails are
    // never upscaled, so the first v2 setup removes them.
    try FileManager.default.createDirectory(
      at: root.appendingPathComponent("thumbs"),
      withIntermediateDirectories: true
    )
    FileManager.default.createFile(
      atPath: root.appendingPathComponent("thumbs/old.png").path,
      contents: Data("fake".utf8)
    )
    FileManager.default.createFile(
      atPath: root.appendingPathComponent("intrinsics.json").path,
      contents: Data("{}".utf8)
    )
    let loader = await RefsPDFIntrinsicsLoader(
      cacheDirectory: root,
      reader: { @Sendable _ in
        RefsPDFIntrinsics(
          pageCount: 5,
          thumbnailPNG: Data([0x89, 0x50, 0x4E, 0x47])
        )
      }
    )
    try FileManager.default.createDirectory(
      at: root, withIntermediateDirectories: true
    )
    let pdf = root.appendingPathComponent("note.pdf")
    FileManager.default.createFile(
      atPath: pdf.path, contents: Data("fake".utf8)
    )
    let loaded = await loader.intrinsics(for: pdf, id: "legacy-check")
    XCTAssertEqual(loaded.pageCount, 5)

    XCTAssertFalse(
      FileManager.default.fileExists(
        atPath: root.appendingPathComponent("intrinsics.json").path
      )
    )
    XCTAssertFalse(
      FileManager.default.fileExists(
        atPath: root.appendingPathComponent("thumbs").path
      )
    )
    XCTAssertTrue(
      FileManager.default.fileExists(
        atPath: root.appendingPathComponent("intrinsics-v2.json").path
      )
    )
    XCTAssertTrue(
      FileManager.default.fileExists(
        atPath: root.appendingPathComponent("thumbs-v2").path
      )
    )
  }

  func testIntrinsicsDiscardDropsInFlightAndAllowsFutureLoads() async throws {
    final class ReadProbe: @unchecked Sendable {
      private let lock = NSLock()
      private var startedStorage = 0
      private var finishedStorage = 0
      private var isOpenStorage = false

      var started: Int {
        lock.withLock { startedStorage }
      }

      var finished: Int {
        lock.withLock { finishedStorage }
      }

      private var isOpen: Bool {
        lock.withLock { isOpenStorage }
      }

      func enter() -> Int {
        lock.withLock {
          startedStorage += 1
          return startedStorage
        }
      }

      func finish() {
        lock.withLock { finishedStorage += 1 }
      }

      func open() {
        lock.withLock { isOpenStorage = true }
      }

      func waitUntilOpen() async {
        let deadline = ContinuousClock.now + .seconds(5)
        while !isOpen, ContinuousClock.now < deadline {
          try? await Task.sleep(for: .milliseconds(10))
        }
      }
    }
    let probe = ReadProbe()
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString)
    let loader = await RefsPDFIntrinsicsLoader(
      cacheDirectory: root,
      reader: { @Sendable _ in
        let readNumber = probe.enter()
        await probe.waitUntilOpen()
        probe.finish()
        return RefsPDFIntrinsics(pageCount: 6 + readNumber)
      }
    )
    try FileManager.default.createDirectory(
      at: root, withIntermediateDirectories: true
    )
    let pdf = root.appendingPathComponent("note.pdf")
    FileManager.default.createFile(
      atPath: pdf.path, contents: Data("fake".utf8)
    )
    let first = Task {
      await loader.intrinsics(for: pdf, id: "roundtrip")
    }
    let deadline = ContinuousClock.now + .seconds(5)
    while probe.started == 0, ContinuousClock.now < deadline {
      try? await Task.sleep(for: .milliseconds(10))
    }
    XCTAssertEqual(probe.started, 1)
    await loader.discard(id: "roundtrip")
    let second = Task {
      await loader.intrinsics(for: pdf, id: "roundtrip")
    }
    let secondDeadline = ContinuousClock.now + .seconds(5)
    while probe.started < 2, ContinuousClock.now < secondDeadline {
      try? await Task.sleep(for: .milliseconds(10))
    }
    XCTAssertEqual(probe.started, 2)
    probe.open()
    let firstValue = await first.value
    XCTAssertEqual(firstValue.pageCount, 7)
    let secondPageCount = await second.value.pageCount
    XCTAssertEqual(secondPageCount, 8)
    let thirdPageCount = await loader.intrinsics(for: pdf, id: "roundtrip").pageCount
    XCTAssertEqual(thirdPageCount, 8)
    XCTAssertEqual(probe.finished, 2)
  }

  func testActionsMenuVariesWithURLsAndAudio() throws {
    let fixtures = makeFixtures()

    let chatSections = RefsActionsMenu.sections(
      for: fixtures.chat,
      audioURL: nil
    )
    XCTAssertEqual(chatSections.count, 3)
    XCTAssertEqual(
      try XCTUnwrap(chatSections.dropFirst().first),
      [.copy, .rename, .linkToday]
    )
    let readyNew = RefsActionsMenu.sections(
      for: fixtures.paper,
      audioURL: nil,
      newState: .isNew
    )
    XCTAssertEqual(
      Array(try XCTUnwrap(readyNew.dropFirst().first).prefix(4)),
      [.copy, .rename, .linkToday, .markSeen]
    )
    let readySeen = RefsActionsMenu.sections(
      for: fixtures.paper,
      audioURL: nil,
      newState: .isNotNew
    )
    XCTAssertTrue(try XCTUnwrap(readySeen.dropFirst().first).contains(.markNew))
    XCTAssertEqual(RefsAction.markSeen.title, "Mark as Seen")
    XCTAssertEqual(RefsAction.markSeen.keyEquivalent, "n")
    XCTAssertEqual(RefsAction.markSeen.keyEquivalentModifierMask, .option)
    XCTAssertEqual(RefsAction.markNew.title, "Mark as New")
    XCTAssertEqual(RefsAction.markNew.keyEquivalentModifierMask, .option)

    let paperURL = fixtures.library.audioURL(for: fixtures.paper)
    XCTAssertNotNil(paperURL)
    let paperSections = RefsActionsMenu.sections(
      for: fixtures.paper,
      audioURL: paperURL
    )
    let paperActions = try XCTUnwrap(paperSections.dropFirst().first)
    XCTAssertTrue(paperActions.contains(.copy))
    XCTAssertTrue(
      paperActions.contains(
        .openSourceURL(URL(string: "https://example.com/post")!)
      ))
    XCTAssertTrue(paperActions.contains(.openNarration(paperURL!)))
  }

  func testActionsMenuEndsWithScanAfterRefresh() {
    let fixtures = makeFixtures()
    let sections = RefsActionsMenu.sections(
      for: fixtures.chat,
      audioURL: nil
    )
    XCTAssertEqual(
      sections.last,
      [.openDefaultApp, .refreshLibrary, .scanLibrary]
    )
    XCTAssertEqual(RefsAction.scanLibrary.title, "Scan for New References")
    XCTAssertEqual(RefsAction.scanLibrary.keyEquivalent, "s")
    XCTAssertEqual(
      RefsAction.scanLibrary.keyEquivalentModifierMask,
      .command
    )
    XCTAssertEqual(RefsAction.linkToday.title, "Link to Today…")
    XCTAssertEqual(RefsAction.linkToday.keyEquivalent, "n")
    XCTAssertEqual(RefsAction.linkToday.keyEquivalentModifierMask, .command)
  }

  func testCopyActionOpensCardAndCopiesItsSelectedRow() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString)
    let vault = root.appendingPathComponent("vault")
    let library = RefsLibrary(
      fetcher: nil,
      snapshotStore: RefsSnapshotStore(
        fileURL: root.appendingPathComponent("refs-snapshot.json")
      ),
      openLogStore: RefsOpenLogStore(
        fileURL: root.appendingPathComponent("refs-open-log.json")
      ),
      newMarkStore: RefsNewMarkStore(
        fileURL: root.appendingPathComponent("refs-new-marks.json")
      ),
      vaultRoot: { vault },
      fileExists: { _ in true },
      spotlight: StubSpotlight(),
      now: { Date() }
    )
    let pasteboard = FakePasteboard()
    let model = RefsPanelModel(
      library: library,
      opener: StubOpener(),
      highlights: StubLocator(),
      pasteboard: pasteboard
    )
    let chat = RefItem(
      id: "ref/chat/today_report.md",
      link: "[[ref/chat/today_report]]",
      rawTitle: "Team Fit Review",
      stem: "team_fit_review",
      kind: .chat,
      state: .reading,
      isBlocked: false,
      pdfPath: "lib/chat/team_fit_review.pdf",
      parentLabel: "sase",
      isAgentReport: true
    )
    model.installForPreviews(
      items: [chat],
      signals: RefsSignals(),
      query: "",
      scope: .all,
      selectedID: chat.id,
      banner: nil,
      refreshState: .idle
    )

    XCTAssertEqual(RefsAction.copy.title, "Copy…")
    XCTAssertEqual(RefsAction.copy.keyEquivalent, "y")
    XCTAssertEqual(RefsAction.copy.keyEquivalentModifierMask, .command)
    XCTAssertEqual(RefsAction.rename.title, "Rename…")
    XCTAssertEqual(RefsAction.rename.keyEquivalent, "r")
    XCTAssertEqual(RefsAction.rename.keyEquivalentModifierMask, [.command, .shift])
    let rowActions = try XCTUnwrap(model.actionsSections().dropFirst().first)
    XCTAssertTrue(rowActions.contains(.rename))
    model.performAction(.copy)
    XCTAssertNotNil(model.copyCard)

    model.handleCopyCardKey(
      characters: "w",
      keyCode: 13,
      modifiers: []
    )
    XCTAssertEqual(pasteboard.strings, ["[[ref/chat/today_report]]"])
    XCTAssertNil(model.copyCard)

    model.performAction(.rename)
    XCTAssertEqual(model.renameCard?.draftStem, "team_fit_review")
    XCTAssertNil(model.copyCard)
  }

  func testShowActionsPresentsWhenARowIsSelected() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString)
    let library = RefsLibrary(
      fetcher: nil,
      snapshotStore: RefsSnapshotStore(
        fileURL: root.appendingPathComponent("refs-snapshot.json")
      ),
      openLogStore: RefsOpenLogStore(
        fileURL: root.appendingPathComponent("refs-open-log.json")
      ),
      newMarkStore: RefsNewMarkStore(
        fileURL: root.appendingPathComponent("refs-new-marks.json")
      ),
      vaultRoot: { root.appendingPathComponent("vault") },
      fileExists: { _ in true },
      spotlight: StubSpotlight(),
      now: { Date() }
    )
    let model = RefsPanelModel(
      library: library,
      opener: StubOpener(),
      highlights: StubLocator()
    )
    // Nothing selected: the key passes through.
    XCTAssertFalse(model.perform(.showActions))

    let chat = RefItem(
      id: "ref/chat/today_report.md",
      link: "[[ref/chat/today_report]]",
      rawTitle: "Team Fit Review",
      stem: "team_fit_review",
      kind: .chat,
      state: .reading,
      isBlocked: false,
      pdfPath: "lib/chat/team_fit_review.pdf",
      parentLabel: "sase",
      isAgentReport: true
    )
    model.installForPreviews(
      items: [chat],
      signals: RefsSignals(),
      query: "",
      scope: .all,
      selectedID: chat.id,
      banner: nil,
      refreshState: .idle
    )
    final class PresentationCount: @unchecked Sendable {
      var count = 0
    }
    let presented = PresentationCount()
    model.actionsPresenter = { presented.count += 1 }
    XCTAssertTrue(model.perform(.showActions))
    XCTAssertEqual(presented.count, 1)
  }

  // MARK: - Fixtures

  private struct FixtureSet {
    var library: RefsLibrary
    var fetcher: FakeRefsFetcher
    var intrinsics: StubIntrinsics
    var chat: RefItem
    var paper: RefItem
  }

  private func makeFixtures() -> FixtureSet {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString)
    let vault = root.appendingPathComponent("vault")
    let fetcher = FakeRefsFetcher()
    let library = RefsLibrary(
      fetcher: fetcher,
      snapshotStore: RefsSnapshotStore(
        fileURL: root.appendingPathComponent("refs-snapshot.json")
      ),
      openLogStore: RefsOpenLogStore(
        fileURL: root.appendingPathComponent("refs-open-log.json")
      ),
      newMarkStore: RefsNewMarkStore(
        fileURL: root.appendingPathComponent("refs-new-marks.json")
      ),
      vaultRoot: { vault },
      fileExists: { _ in true },
      spotlight: StubSpotlight(),
      now: { Date() }
    )
    let chat = RefItem(
      id: "ref/chat/today_report.md",
      link: "[[ref/chat/today_report]]",
      rawTitle: "Team Fit Review",
      stem: "team_fit_review",
      kind: .chat,
      state: .reading,
      isBlocked: false,
      pdfPath: "lib/chat/team_fit_review.pdf",
      parentLabel: "sase",
      isAgentReport: true
    )
    let paper = RefItem(
      id: "ref/papers/harness_buy.md",
      link: "[[ref/papers/harness_buy]]",
      rawTitle: "What Does a Harness Buy You?",
      stem: "harness_buy",
      kind: .paper,
      state: .ready,
      isBlocked: false,
      pdfPath: "lib/papers/harness_buy.pdf",
      author: "Yangze Liu",
      audioPath: "lib/papers/harness_buy.m4a",
      urls: ["https://example.com/post"]
    )
    library.installSnapshotForPreviews(
      items: [chat, paper],
      signals: RefsSignals(),
      refreshState: .idle
    )
    let intrinsics = StubIntrinsics(
      result: RefsPDFIntrinsics(
        pageCount: 22,
        outlineHeadings: ["Method", "Results"],
        leadText: "Abstract\nWe study harness reuse.",
        wordEstimate: 22 * 230,
        thumbnailPNG: nil
      ))
    return FixtureSet(
      library: library,
      fetcher: fetcher,
      intrinsics: intrinsics,
      chat: chat,
      paper: paper
    )
  }

  private func waitForContent(
    _ loader: RefsInspectorLoader,
    id: String
  ) async {
    let deadline = Date().addingTimeInterval(5)
    while Date() < deadline {
      if loader.content(for: id) != nil {
        return
      }
      try? await Task.sleep(nanoseconds: 20_000_000)
    }
    XCTFail("inspector content not ready before timeout")
  }

  private func makePreviewModel() -> RefsPanelModel {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString)
    let vault = root.appendingPathComponent("vault")
    let library = RefsLibrary(
      fetcher: nil,
      snapshotStore: RefsSnapshotStore(
        fileURL: root.appendingPathComponent("refs-snapshot.json")
      ),
      openLogStore: RefsOpenLogStore(
        fileURL: root.appendingPathComponent("refs-open-log.json")
      ),
      newMarkStore: RefsNewMarkStore(
        fileURL: root.appendingPathComponent("refs-new-marks.json")
      ),
      vaultRoot: { vault },
      fileExists: { _ in true },
      spotlight: StubSpotlight(),
      now: { Date() }
    )
    return RefsPanelModel(
      library: library,
      opener: StubOpener(),
      highlights: StubLocator()
    )
  }

  private func previewChat() -> RefItem {
    RefItem(
      id: "ref/chat/today_report.md",
      link: "[[ref/chat/today_report]]",
      rawTitle: "Team Fit Review",
      stem: "team_fit_review",
      kind: .chat,
      state: .reading,
      isBlocked: false,
      pdfPath: "lib/chat/team_fit_review.pdf",
      parentLabel: "sase",
      isAgentReport: true
    )
  }

  private func fixtureData(_ name: String) throws -> Data {
    let source = URL(fileURLWithPath: #filePath)
    let packageRoot =
      source
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    return try Data(
      contentsOf: packageRoot.appendingPathComponent("Tests/Fixtures/\(name)")
    )
  }

  private func waitForCalls(
    _ intrinsics: StubIntrinsics,
    count: Int
  ) async {
    let deadline = Date().addingTimeInterval(5)
    while Date() < deadline {
      if intrinsics.calls.count == count {
        return
      }
      try? await Task.sleep(nanoseconds: 20_000_000)
    }
    XCTFail("intrinsics calls not ready before timeout")
  }
}

enum RefsTestError: Error {
  case boom
}

final class FakeRefsFetcher: RefsFetching, @unchecked Sendable {
  private let lock = NSLock()
  private(set) var showPaths: [String] = []
  private(set) var renameCalls: [(notePath: String, name: String)] = []
  private(set) var todayLinkCalls:
    [(notePath: String, selector: RefsTodayLinkSelector, dryRun: Bool)] = []
  var showError: Error?
  var renameError: Error?
  var renameResponse = RefsRenameResponse()
  var todayLinkResponses: [RefsTodayLinkResponse] = []
  var todayLinkResponse = RefsTodayLinkResponse()
  var todayLinkError: Error?
  var todayLinkDelayNanoseconds: UInt64 = 0
  var todayLinkHandler:
    (@Sendable (String, RefsTodayLinkSelector, Bool) async throws -> RefsTodayLinkResponse)?
  var listResponse = RefsListResponse(schemaVersion: 1)
  var listError: Error?
  var planResponse = RefsPlanResponse(schemaVersion: 2)
  var planError: Error?
  var showDelayNanoseconds: UInt64 = 50_000_000
  var renameDelayNanoseconds: UInt64 = 0
  /// When set, the returned row uses this path instead of the
  /// requested one, so exact-path matching can fail.
  var showRowPath: String?
  /// When set, `show` returns this envelope instead of the default row.
  var showResponse: RefsShowResponse?

  func list(gitDates: Bool) async throws -> RefsListResponse {
    if let listError { throw listError }
    return listResponse
  }

  func plan() async throws -> RefsPlanResponse {
    if let planError { throw planError }
    return planResponse
  }

  var scanResult: RefsScanResponse = RefsScanResponse(schemaVersion: 1)
  var scanError: Error?
  var scanDelayNanoseconds: UInt64 = 0

  func scan() async throws -> RefsScanResponse {
    if scanDelayNanoseconds > 0 {
      try await Task.sleep(nanoseconds: scanDelayNanoseconds)
    }
    if let scanError {
      throw scanError
    }
    return scanResult
  }

  func rename(notePath: String, name: String) async throws -> RefsRenameResponse {
    lock.withLock { renameCalls.append((notePath, name)) }
    if renameDelayNanoseconds > 0 {
      try await Task.sleep(nanoseconds: renameDelayNanoseconds)
    }
    if let renameError {
      throw renameError
    }
    return renameResponse
  }

  func linkToToday(
    notePath: String, selector: RefsTodayLinkSelector, dryRun: Bool
  ) async throws -> RefsTodayLinkResponse {
    lock.withLock { todayLinkCalls.append((notePath, selector, dryRun)) }
    if todayLinkDelayNanoseconds > 0 {
      try await Task.sleep(nanoseconds: todayLinkDelayNanoseconds)
    }
    if let handler = lock.withLock({ todayLinkHandler }) {
      return try await handler(notePath, selector, dryRun)
    }
    if let todayLinkError { throw todayLinkError }
    return lock.withLock {
      if !todayLinkResponses.isEmpty { return todayLinkResponses.removeFirst() }
      return todayLinkResponse
    }
  }

  func show(path: String) async throws -> RefsShowResponse {
    lock.withLock { showPaths.append(path) }
    try await Task.sleep(nanoseconds: showDelayNanoseconds)
    if let showError {
      throw showError
    }
    if let showResponse {
      return showResponse
    }
    return RefsShowResponse(
      schemaVersion: 1,
      refs: [
        RefsShowRow(
          path: showRowPath ?? path,
          annotations: [
            RefsShowAnnotation(
              pageLabel: "3",
              kind: "highlight",
              quote: "The pipeline drains while the child runs.",
              comment: "Key insight for the fetcher."
            )
          ],
          tasks: [RefsShowTask(checked: false, mark: " ", text: "Follow up.")],
          annotationsStatus: "parsed"
        )
      ])
  }
}

final class StubAnnotationImages: RefsAnnotationImageProviding, @unchecked Sendable {
  private let lock = NSLock()
  private(set) var metricURLs: [URL] = []
  private(set) var imageURLs: [URL] = []
  private(set) var imageCompletions: [URL] = []
  var metricsByLastComponent: [String: RefsImageMetrics] = [:]
  var imageByLastComponent: [String: NSImage] = [:]
  var metricsDelayNanoseconds: UInt64 = 0
  var imageDelayNanoseconds: UInt64 = 0
  private var holdingImages = false
  private var holdWaiters: [CheckedContinuation<Void, Never>] = []

  var metricURLLastComponents: [String] {
    lock.withLock { metricURLs.map(\.lastPathComponent) }
  }

  var imageURLCount: Int {
    lock.withLock { imageURLs.count }
  }

  var imageCompletionCount: Int {
    lock.withLock { imageCompletions.count }
  }

  func beginHoldingImages() {
    lock.withLock { holdingImages = true }
  }

  func releaseHeldImages() {
    let waiters: [CheckedContinuation<Void, Never>]
    lock.lock()
    holdingImages = false
    waiters = holdWaiters
    holdWaiters = []
    lock.unlock()
    for waiter in waiters {
      waiter.resume()
    }
  }

  func metrics(for url: URL) async -> RefsImageMetrics? {
    lock.withLock { metricURLs.append(url) }
    if metricsDelayNanoseconds > 0 {
      try? await Task.sleep(nanoseconds: metricsDelayNanoseconds)
    }
    return lock.withLock { metricsByLastComponent[url.lastPathComponent] }
  }

  func image(for url: URL, maxPixel: Int) async -> NSImage? {
    lock.withLock { imageURLs.append(url) }
    let shouldHold = lock.withLock { holdingImages }
    if shouldHold {
      await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
        lock.lock()
        if holdingImages {
          holdWaiters.append(cont)
          lock.unlock()
        } else {
          lock.unlock()
          cont.resume()
        }
      }
    }
    if imageDelayNanoseconds > 0 {
      try? await Task.sleep(nanoseconds: imageDelayNanoseconds)
    }
    let image = lock.withLock { imageByLastComponent[url.lastPathComponent] }
    lock.withLock { imageCompletions.append(url) }
    return image
  }
}

func makeTestImage(size: NSSize, color: NSColor, hasAlpha: Bool = false) -> NSImage {
  let pixelsWide = max(1, Int(size.width.rounded()))
  let pixelsHigh = max(1, Int(size.height.rounded()))
  // Four-sample RGBA is the supported bitmap for `NSRect.fill()` after
  // `color.setFill()`. A three-sample RGB bitmap traps (signal 5).
  let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: pixelsWide,
    pixelsHigh: pixelsHigh,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
  )!
  NSGraphicsContext.saveGraphicsState()
  NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
  if hasAlpha {
    NSColor.clear.setFill()
    NSRect(x: 0, y: 0, width: pixelsWide, height: pixelsHigh).fill()
  }
  color.setFill()
  NSRect(x: 0, y: 0, width: pixelsWide, height: pixelsHigh).fill()
  NSGraphicsContext.restoreGraphicsState()
  let image = NSImage(size: size)
  image.addRepresentation(rep)
  return image
}

func writePNG(_ image: NSImage, to url: URL) throws {
  let tiff = try XCTUnwrap(image.tiffRepresentation)
  let rep = try XCTUnwrap(NSBitmapImageRep(data: tiff))
  let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
  try png.write(to: url)
}

@discardableResult
func waitUntil(
  timeout: TimeInterval,
  file: StaticString = #filePath,
  line: UInt = #line,
  _ predicate: @escaping () -> Bool
) async -> Bool {
  let deadline = Date().addingTimeInterval(timeout)
  while Date() < deadline {
    if predicate() {
      return true
    }
    try? await Task.sleep(nanoseconds: 20_000_000)
  }
  XCTFail("timed out waiting", file: file, line: line)
  return false
}

@discardableResult
func waitUntilRunLoop(
  timeout: TimeInterval,
  file: StaticString = #filePath,
  line: UInt = #line,
  _ predicate: () -> Bool
) -> Bool {
  let deadline = Date().addingTimeInterval(timeout)
  while Date() < deadline {
    if predicate() {
      return true
    }
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.02))
  }
  XCTFail("timed out waiting", file: file, line: line)
  return false
}

final class StubIntrinsics: RefsPDFIntrinsicsProviding, @unchecked Sendable {
  private let lock = NSLock()
  private(set) var calls: [String] = []
  var result: RefsPDFIntrinsics

  init(result: RefsPDFIntrinsics) {
    self.result = result
  }

  func intrinsics(for pdfURL: URL, id: String) async -> RefsPDFIntrinsics {
    lock.withLock { calls.append(id) }
    return result
  }
}

final class FakePasteboard: RefsPasteboardWriting, @unchecked Sendable {
  private let lock = NSLock()
  private(set) var strings: [String] = []
  private(set) var payloads: [RefsClipboardPayload] = []
  var failWrites = false

  func write(_ payload: RefsClipboardPayload) -> Bool {
    lock.withLock {
      if failWrites {
        return false
      }
      payloads.append(payload)
      if case .text(let string) = payload {
        strings.append(string)
      }
      return true
    }
  }
}

private struct StubOpener: RefsOpening {
  func openInHighlights(
    _ pdf: URL,
    app: URL,
    completion: @escaping (Error?) -> Void
  ) {
    completion(nil)
  }

  func openNote(_ url: URL) {}

  func reveal(_ url: URL) {}

  func openWithDefaultApp(
    _ url: URL,
    completion: @escaping (Error?) -> Void
  ) {
    completion(nil)
  }
}

private struct StubLocator: RefsHighlightsLocating {
  func highlightsAppURL() -> URL? {
    nil
  }
}

private struct StubSpotlight: RefsSpotlightProviding {
  func sweep(
    _ requests: [RefsSpotlightRequest]
  ) async -> [String: RefsSpotlightFacts] {
    [:]
  }
}
