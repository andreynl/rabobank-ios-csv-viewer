import Foundation
import Observation

@Observable
@MainActor
final class CSVViewModel {
  private struct LoadRequest: Sendable {
    let source: CSVSource
    let filename: String
  }

  private(set) var state: CSVViewState = .idle
  private(set) var displayedFilename = ""
  private(set) var headers: [String] = []
  private(set) var availableRowCount = 0
  private(set) var fractionCompleted: Double?
  private(set) var isComplete = false
  private(set) var pageSize = CSVPageConfiguration.defaultPageSize
  private(set) var pageLoadErrorMessage: String?

  private let loadCSV: any LoadPagedCSVUseCaseProtocol
  private let maximumCachedPages: Int
  private var loadingTask: Task<Void, Never>?
  private var currentSession: CSVLoadSession?
  private var pages: [Int: CSVRowPage] = [:]
  private var pageRecency: [Int] = []
  private var inFlightPages: Set<Int> = []
  private var failedPageRows: [Int: Int] = [:]
  private var hasRequestedBundledSample = false
  private var requestGeneration = 0
  private var lastLoadRequest: LoadRequest?

  var canRetryLoad: Bool {
    lastLoadRequest != nil
  }

  init(loadCSV: any LoadPagedCSVUseCaseProtocol, maximumCachedPages: Int = 3) {
    self.loadCSV = loadCSV
    self.maximumCachedPages = max(1, maximumCachedPages)
  }

  func loadBundledSampleIfNeeded() {
    guard !hasRequestedBundledSample else { return }
    hasRequestedBundledSample = true
    load(source: .bundled(name: "issues", extension: "csv"), filename: "issues.csv")
  }

  func importFile(at url: URL) {
    load(source: .file(url), filename: url.lastPathComponent)
  }

  func handleImportFailure(_ error: Error) {
    replaceCurrentLoad()
    lastLoadRequest = nil
    state = .failure("The selected file could not be imported.")
  }

  func retryLoad() {
    guard let lastLoadRequest else { return }
    load(lastLoadRequest)
  }

  func row(at rowIndex: Int) -> [String]? {
    guard rowIndex >= 0 else { return nil }
    for page in pages.values where rowIndex >= page.startRow {
      let offset = rowIndex - page.startRow
      if page.rows.indices.contains(offset) { return page.rows[offset] }
    }
    return nil
  }

  func loadPage(containing rowIndex: Int) async {
    guard rowIndex >= 0, rowIndex < availableRowCount, let session = currentSession else { return }
    let pageIndex = rowIndex / pageSize
    if pages[pageIndex] != nil {
      markRecentlyUsed(pageIndex)
      return
    }
    guard inFlightPages.insert(pageIndex).inserted else { return }
    defer { inFlightPages.remove(pageIndex) }

    do {
      let page = try await session.pages.page(containing: rowIndex)
      guard session === currentSession else { return }
      pages[page.index] = page
      failedPageRows.removeValue(forKey: page.index)
      updatePageLoadErrorMessage()
      markRecentlyUsed(page.index)
      evictPagesIfNeeded()
    } catch is CancellationError {
      return
    } catch {
      guard session === currentSession else { return }
      failedPageRows[pageIndex] = rowIndex
      updatePageLoadErrorMessage()
    }
  }

  func retryFailedPages() async {
    let rowIndexes = failedPageRows.values.sorted()
    for rowIndex in rowIndexes {
      await loadPage(containing: rowIndex)
    }
  }

  private func load(source: CSVSource, filename: String) {
    load(LoadRequest(source: source, filename: filename))
  }

  private func load(_ request: LoadRequest) {
    replaceCurrentLoad()
    lastLoadRequest = request
    let generation = requestGeneration
    displayedFilename = request.filename
    state = .loading

    loadingTask = Task { [loadCSV] in
      do {
        let session = try await loadCSV.execute(source: request.source)
        guard generation == requestGeneration else {
          session.cancel()
          await session.pages.close()
          return
        }
        currentSession = session
        pageSize = session.pages.pageSize
        for try await progress in session.updates {
          guard generation == requestGeneration else { return }
          apply(progress)
        }
      } catch is CancellationError {
        return
      } catch {
        guard generation == requestGeneration else { return }
        state = .failure(Self.message(for: error))
      }
    }
  }

  private func replaceCurrentLoad() {
    requestGeneration += 1
    loadingTask?.cancel()
    loadingTask = nil
    if let session = currentSession {
      session.cancel()
      Task { await session.pages.close() }
    }
    currentSession = nil
    headers = []
    availableRowCount = 0
    fractionCompleted = nil
    isComplete = false
    pageSize = CSVPageConfiguration.defaultPageSize
    pages.removeAll(keepingCapacity: true)
    pageRecency.removeAll(keepingCapacity: true)
    inFlightPages.removeAll(keepingCapacity: true)
    failedPageRows.removeAll(keepingCapacity: true)
    pageLoadErrorMessage = nil
  }

  private func apply(_ progress: CSVLoadProgress) {
    headers = progress.headers
    availableRowCount = max(availableRowCount, progress.availableRowCount)
    fractionCompleted = progress.fractionCompleted
    isComplete = progress.isComplete
    if progress.isComplete {
      state = progress.headers.isEmpty ? .empty : .loaded
    } else if !progress.headers.isEmpty {
      state = .streaming
    }
  }

  private func markRecentlyUsed(_ pageIndex: Int) {
    pageRecency.removeAll { $0 == pageIndex }
    pageRecency.append(pageIndex)
  }

  private func evictPagesIfNeeded() {
    while pages.count > maximumCachedPages, let oldest = pageRecency.first {
      pageRecency.removeFirst()
      pages.removeValue(forKey: oldest)
    }
  }

  private func updatePageLoadErrorMessage() {
    pageLoadErrorMessage = failedPageRows.isEmpty
      ? nil
      : "Some rows could not be loaded."
  }

  private static func message(for error: Error) -> String {
    switch error as? CSVLoadingError {
    case .resourceNotFound: "The CSV file could not be found."
    case .accessDenied: "Access to the selected file was denied."
    case .readFailed: "The file could not be read."
    case .invalidEncoding: "The file is not valid UTF-8 text."
    case .malformedCSV: "The file contains malformed CSV data."
    case .resourceLimitExceeded: "The CSV contains a field, row, or page that is too large."
    case .storageFailed: "The CSV data could not be stored temporarily."
    case nil: "The CSV file could not be loaded."
    }
  }
}
