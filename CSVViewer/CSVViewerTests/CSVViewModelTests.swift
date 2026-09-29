import Foundation
import Synchronization
import Testing
@testable import CSVViewer

@MainActor
struct CSVViewModelTests {
  @Test func publishesProgressiveStateAndFinalRowCount() async {
    let setup = await makeSetup()

    setup.stream.yield(progress(headers: ["name"], rows: 0, fraction: 0.1))
    await waitUntil { setup.viewModel.state == .streaming }
    setup.stream.yield(progress(headers: ["name"], rows: 501, fraction: 1, complete: true))
    setup.stream.finish()
    await waitUntil { setup.viewModel.state == .loaded }

    #expect(setup.viewModel.headers == ["name"])
    #expect(setup.viewModel.availableRowCount == 501)
    #expect(setup.viewModel.fractionCompleted == 1)
    #expect(setup.viewModel.isComplete)
    #expect(setup.viewModel.displayedFilename == "issues.csv")
  }

  @Test func headerOnlyDocumentDoesNotRequestPageZero() async {
    let setup = await makeSetup()

    setup.stream.yield(progress(headers: ["name"], rows: 0, fraction: 1, complete: true))
    setup.stream.finish()
    await waitUntil { setup.viewModel.state == .loaded }

    #expect(await setup.provider.requestedRows.isEmpty)
  }

  @Test func emptyDocumentUsesEmptyState() async {
    let setup = await makeSetup()
    setup.stream.yield(progress(headers: [], rows: 0, fraction: 1, complete: true))
    setup.stream.finish()
    await waitUntil { setup.viewModel.state == .empty }
  }

  @Test func concurrentRowsFromOnePageAreFetchedOnce() async {
    let page = CSVRowPage(index: 0, startRow: 0, rows: [["Theo"], ["Fiona"]])
    let provider = PageProviderStub(pages: [0: page], delay: .milliseconds(20))
    let setup = await makeSetup(provider: provider)
    setup.stream.yield(progress(headers: ["name"], rows: 2, fraction: 1, complete: true))
    setup.stream.finish()
    await waitUntil { setup.viewModel.state == .loaded }

    async let first: Void = setup.viewModel.loadPage(containing: 0)
    async let second: Void = setup.viewModel.loadPage(containing: 1)
    _ = await (first, second)

    #expect(await provider.requestedRows.count == 1)
    #expect(setup.viewModel.row(at: 0) == ["Theo"])
    #expect(setup.viewModel.row(at: 1) == ["Fiona"])
  }

  @Test func usesProviderPageSizeForRequestCoalescing() async {
    let page = CSVRowPage(index: 0, startRow: 0, rows: [["a"], ["b"]])
    let provider = PageProviderStub(pages: [0: page], delay: .milliseconds(20), pageSize: 2)
    let setup = await makeSetup(provider: provider)
    setup.stream.yield(progress(headers: ["name"], rows: 2, fraction: 1, complete: true))
    setup.stream.finish()
    await waitUntil { setup.viewModel.state == .loaded }

    async let first: Void = setup.viewModel.loadPage(containing: 0)
    async let second: Void = setup.viewModel.loadPage(containing: 1)
    _ = await (first, second)

    #expect(setup.viewModel.pageSize == 2)
    #expect(await provider.requestedRows.count == 1)
  }

  @Test func evictedPageCanBeFetchedAgain() async {
    let pages = Dictionary(uniqueKeysWithValues: (0..<4).map { index in
      let start = index * 500
      return (index, CSVRowPage(index: index, startRow: start, rows: [["row-\(start)"]]))
    })
    let provider = PageProviderStub(pages: pages)
    let setup = await makeSetup(provider: provider)
    setup.stream.yield(progress(headers: ["name"], rows: 1_501, fraction: 1, complete: true))
    setup.stream.finish()
    await waitUntil { setup.viewModel.state == .loaded }

    for row in [0, 500, 1_000, 1_500] { await setup.viewModel.loadPage(containing: row) }
    #expect(setup.viewModel.row(at: 0) == nil)
    await setup.viewModel.loadPage(containing: 0)

    #expect(setup.viewModel.row(at: 0) == ["row-0"])
    #expect(await provider.requestedRows.filter { $0 == 0 }.count == 2)
  }

  @Test func pageReadFailureKeepsLoadedState() async {
    let provider = PageProviderStub(
      pages: [:],
      failuresBeforeSuccess: [0: 1]
    )
    let setup = await makeSetup(provider: provider)
    setup.stream.yield(progress(headers: ["name"], rows: 1, fraction: 1, complete: true))
    setup.stream.finish()
    await waitUntil { setup.viewModel.state == .loaded }

    await setup.viewModel.loadPage(containing: 0)

    #expect(setup.viewModel.state == .loaded)
    #expect(setup.viewModel.pageLoadErrorMessage != nil)
  }

  @Test func coalescesFailureAndRetriesPageOnce() async {
    let page = CSVRowPage(index: 0, startRow: 0, rows: [["Theo"], ["Fiona"]])
    let provider = PageProviderStub(
      pages: [0: page],
      delay: .milliseconds(20),
      pageSize: 2,
      failuresBeforeSuccess: [0: 1]
    )
    let setup = await makeSetup(provider: provider)
    setup.stream.yield(progress(headers: ["name"], rows: 2, fraction: 1, complete: true))
    setup.stream.finish()
    await waitUntil { setup.viewModel.state == .loaded }

    async let first: Void = setup.viewModel.loadPage(containing: 0)
    async let second: Void = setup.viewModel.loadPage(containing: 1)
    _ = await (first, second)
    await setup.viewModel.retryFailedPages()

    #expect(await provider.requestedRows.count == 2)
    #expect(setup.viewModel.row(at: 0) == ["Theo"])
    #expect(setup.viewModel.row(at: 1) == ["Fiona"])
    #expect(setup.viewModel.pageLoadErrorMessage == nil)
  }

  @Test func newImportClearsPageReadFailure() async {
    let provider = PageProviderStub(
      pages: [:],
      failuresBeforeSuccess: [0: 1]
    )
    let setup = await makeSetup(provider: provider)
    setup.stream.yield(progress(headers: ["name"], rows: 1, fraction: 1, complete: true))
    setup.stream.finish()
    await waitUntil { setup.viewModel.state == .loaded }
    await setup.viewModel.loadPage(containing: 0)
    #expect(setup.viewModel.pageLoadErrorMessage != nil)

    setup.viewModel.importFile(at: URL(fileURLWithPath: "/tmp/new.csv"))

    #expect(setup.viewModel.state == .loading)
    #expect(setup.viewModel.pageLoadErrorMessage == nil)
  }

  @Test func replacementCancelsAndClosesPreviousSession() async {
    let useCase = ControllablePagedLoadUseCase()
    let oldProvider = PageProviderStub(pages: [:])
    let oldStream = ProgressStream()
    let viewModel = CSVViewModel(loadCSV: useCase)
    let bundled = CSVSource.bundled(name: "issues", extension: "csv")
    let url = URL(fileURLWithPath: "/tmp/replacement.csv")
    viewModel.loadBundledSampleIfNeeded()
    await useCase.waitUntilRequested(bundled)
    await useCase.succeed(bundled, with: oldStream.session(pages: oldProvider))
    oldStream.yield(progress(headers: ["old"], rows: 0, fraction: 0.1))
    await waitUntil { viewModel.state == .streaming }

    viewModel.importFile(at: url)
    await useCase.waitUntilRequested(.file(url))
    await waitUntil {
      let isClosed = await oldProvider.isClosed
      return oldStream.isCancelled && isClosed
    }

    #expect(viewModel.state == .loading)
    #expect(viewModel.displayedFilename == "replacement.csv")
  }

  @Test func storageFailureUsesReadableState() async {
    let useCase = ControllablePagedLoadUseCase()
    let viewModel = CSVViewModel(loadCSV: useCase)
    let source = CSVSource.bundled(name: "issues", extension: "csv")
    viewModel.loadBundledSampleIfNeeded()
    await useCase.waitUntilRequested(source)
    await useCase.fail(source, with: CSVLoadingError.storageFailed)
    await waitUntil { viewModel.state == .failure("The CSV data could not be stored temporarily.") }
  }

  @Test func resourceLimitFailureUsesReadableState() async {
    let useCase = ControllablePagedLoadUseCase()
    let viewModel = CSVViewModel(loadCSV: useCase)
    let source = CSVSource.bundled(name: "issues", extension: "csv")
    viewModel.loadBundledSampleIfNeeded()
    await useCase.waitUntilRequested(source)
    await useCase.fail(source, with: CSVLoadingError.resourceLimitExceeded)

    await waitUntil {
      viewModel.state == .failure("The CSV contains a field, row, or page that is too large.")
    }
  }

  @Test func staleFailureCannotOverwriteNewerImport() async {
    let useCase = ControllablePagedLoadUseCase()
    let viewModel = CSVViewModel(loadCSV: useCase)
    let bundled = CSVSource.bundled(name: "issues", extension: "csv")
    let importedURL = URL(fileURLWithPath: "/tmp/new.csv")
    viewModel.loadBundledSampleIfNeeded()
    await useCase.waitUntilRequested(bundled)

    viewModel.importFile(at: importedURL)
    await useCase.waitUntilRequested(.file(importedURL))
    await useCase.fail(bundled, with: CSVLoadingError.readFailed)
    await Task.yield()

    #expect(viewModel.state == .loading)
    #expect(viewModel.displayedFilename == "new.csv")
  }

  @Test func bundledSampleLoadsOnlyOnce() async {
    let useCase = ControllablePagedLoadUseCase()
    let viewModel = CSVViewModel(loadCSV: useCase)
    let source = CSVSource.bundled(name: "issues", extension: "csv")
    viewModel.loadBundledSampleIfNeeded()
    viewModel.loadBundledSampleIfNeeded()
    await useCase.waitUntilRequested(source)
    #expect(await useCase.requestCount(for: source) == 1)
  }

  private func makeSetup(
    provider: PageProviderStub = PageProviderStub(pages: [:])
  ) async -> (viewModel: CSVViewModel, stream: ProgressStream, provider: PageProviderStub) {
    let useCase = ControllablePagedLoadUseCase()
    let stream = ProgressStream()
    let viewModel = CSVViewModel(loadCSV: useCase)
    let source = CSVSource.bundled(name: "issues", extension: "csv")
    viewModel.loadBundledSampleIfNeeded()
    await useCase.waitUntilRequested(source)
    await useCase.succeed(source, with: stream.session(pages: provider))
    return (viewModel, stream, provider)
  }

  private func progress(
    headers: [String], rows: Int, fraction: Double?, complete: Bool = false
  ) -> CSVLoadProgress {
    CSVLoadProgress(
      headers: headers,
      availableRowCount: rows,
      fractionCompleted: fraction,
      isComplete: complete
    )
  }

  private func waitUntil(_ predicate: @escaping @MainActor () async -> Bool) async {
    for _ in 0..<1_000 {
      if await predicate() { return }
      await Task.yield()
    }
    Issue.record("Condition was not met")
  }
}

private actor ControllablePagedLoadUseCase: LoadPagedCSVUseCaseProtocol {
  private struct Request {
    let source: CSVSource
    let continuation: CheckedContinuation<CSVLoadSession, Error>
  }
  private var requests: [Request] = []
  private var sources: [CSVSource] = []

  func execute(source: CSVSource) async throws -> CSVLoadSession {
    sources.append(source)
    return try await withCheckedThrowingContinuation { requests.append(Request(source: source, continuation: $0)) }
  }

  func waitUntilRequested(_ source: CSVSource) async {
    for _ in 0..<1_000 {
      if sources.contains(source) { return }
      await Task.yield()
    }
    Issue.record("Expected request for \(source)")
  }

  func requestCount(for source: CSVSource) -> Int { sources.filter { $0 == source }.count }
  func succeed(_ source: CSVSource, with session: CSVLoadSession) { resume(source, .success(session)) }
  func fail(_ source: CSVSource, with error: Error) { resume(source, .failure(error)) }

  private func resume(_ source: CSVSource, _ result: Result<CSVLoadSession, Error>) {
    guard let index = requests.firstIndex(where: { $0.source == source }) else { return }
    requests.remove(at: index).continuation.resume(with: result)
  }
}

private final class ProgressStream: @unchecked Sendable {
  private struct State {
    var continuation: AsyncThrowingStream<CSVLoadProgress, Error>.Continuation?
    var cancelled = false
  }
  private let state = Mutex(State())
  var isCancelled: Bool { state.withLock(\.cancelled) }

  func session(pages: any CSVPageProviding) -> CSVLoadSession {
    let updates = AsyncThrowingStream<CSVLoadProgress, Error> { continuation in
      state.withLock { $0.continuation = continuation }
    }
    return CSVLoadSession(updates: updates, pages: pages) { [weak self] in
      self?.cancel()
    }
  }

  func yield(_ progress: CSVLoadProgress) {
    _ = state.withLock { $0.continuation?.yield(progress) }
  }
  func finish() { state.withLock { $0.continuation?.finish() } }

  private func cancel() {
    state.withLock { value in
      value.cancelled = true
      value.continuation?.finish()
    }
  }
}

private actor PageProviderStub: CSVPageProviding {
  nonisolated let pageSize: Int
  private let pages: [Int: CSVRowPage]
  private let delay: Duration
  private var failuresBeforeSuccess: [Int: Int]
  private(set) var requestedRows: [Int] = []
  private(set) var isClosed = false

  init(
    pages: [Int: CSVRowPage],
    delay: Duration = .zero,
    pageSize: Int = CSVPageConfiguration.defaultPageSize,
    failuresBeforeSuccess: [Int: Int] = [:]
  ) {
    self.pages = pages
    self.delay = delay
    self.pageSize = pageSize
    self.failuresBeforeSuccess = failuresBeforeSuccess
  }

  func page(containing rowIndex: Int) async throws -> CSVRowPage {
    requestedRows.append(rowIndex)
    if delay > .zero { try await Task.sleep(for: delay) }
    let pageIndex = rowIndex / pageSize
    if let remainingFailures = failuresBeforeSuccess[pageIndex], remainingFailures > 0 {
      failuresBeforeSuccess[pageIndex] = remainingFailures - 1
      throw CSVPageStoreError.persistenceFailed
    }
    guard let page = pages[pageIndex] else { throw CSVPageStoreError.pageNotFound(rowIndex) }
    return page
  }

  func close() async { isClosed = true }
}
