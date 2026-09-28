import Foundation
import Synchronization

struct FileCSVRepository: CSVRepository, PagedCSVRepository, Sendable {
  typealias PageStoreFactory = @Sendable () throws -> any CSVPageStore

  private let parser: any CSVParsing
  private let bundle: Bundle
  private let urlAccess: any SecurityScopedURLAccessing
  private let pageStoreFactory: PageStoreFactory

  init(
    parser: any CSVParsing,
    bundle: Bundle = .main,
    urlAccess: any SecurityScopedURLAccessing = SecurityScopedURLAccess(),
    pageStoreFactory: @escaping PageStoreFactory = FileCSVRepository.makeDefaultPageStore
  ) {
    self.parser = parser
    self.bundle = bundle
    self.urlAccess = urlAccess
    self.pageStoreFactory = pageStoreFactory
  }

  func loadSession(from source: CSVSource) async throws -> CSVLoadSession {
    let (url, needsSecurityScope) = try sourceURL(for: source)
    let store = try pageStoreFactory()
    let taskController = SessionTaskController()

    let updates = AsyncThrowingStream<CSVLoadProgress, Error> { continuation in
      let task = Task.detached(priority: .userInitiated) {
        do {
          if needsSecurityScope {
            try await urlAccess.withAccess(to: url) { scopedURL in
              try await producePages(from: scopedURL, store: store, continuation: continuation)
            }
          } else {
            try await producePages(from: url, store: store, continuation: continuation)
          }
          continuation.finish()
        } catch {
          await store.close()
          continuation.finish(throwing: mapStreamingError(error))
        }
      }
      taskController.set(task)
      continuation.onTermination = { termination in
        if case .cancelled = termination {
          taskController.cancel()
        }
      }
    }

    return CSVLoadSession(updates: updates, pages: store) {
      taskController.cancel()
      Task { await store.close() }
    }
  }

  func load(from source: CSVSource) async throws -> CSVDocument {
    switch source {
    case let .bundled(name, fileExtension):
      guard let url = bundle.url(forResource: name, withExtension: fileExtension) else {
        throw CSVLoadingError.resourceNotFound
      }
      return try await readAndParse(url)

    case let .file(url):
      return try await urlAccess.withAccess(to: url) { scopedURL in
        try await readAndParse(scopedURL)
      }
    }
  }

  private func readAndParse(_ url: URL) async throws -> CSVDocument {
    do {
      return try await Task.detached(priority: .userInitiated) { [parser] in
        let data = try Data(contentsOf: url)
        return try parser.parse(data: data)
      }.value
    } catch CSVParserError.invalidUTF8 {
      throw CSVLoadingError.invalidEncoding
    } catch is CSVParserError {
      throw CSVLoadingError.malformedCSV
    } catch let error as CSVLoadingError {
      throw error
    } catch {
      throw CSVLoadingError.readFailed
    }
  }

  private func sourceURL(for source: CSVSource) throws -> (URL, Bool) {
    switch source {
    case let .bundled(name, fileExtension):
      guard let url = bundle.url(forResource: name, withExtension: fileExtension) else {
        throw CSVLoadingError.resourceNotFound
      }
      return (url, false)
    case let .file(url):
      return (url, true)
    }
  }

  private func producePages(
    from url: URL,
    store: any CSVPageStore,
    continuation: AsyncThrowingStream<CSVLoadProgress, Error>.Continuation
  ) async throws {
    let values = try url.resourceValues(forKeys: [.fileSizeKey])
    let fileSize = values.fileSize ?? 0
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }

    var streamingParser = StreamingCSVParser()
    var headers: [String] = []
    var pendingRows: [[String]] = []
    var availableRowCount = 0
    var bytesRead = 0

    while let chunk = try handle.read(upToCount: 64 * 1024), !chunk.isEmpty {
      try Task.checkCancellation()
      bytesRead += chunk.count
      let result = try streamingParser.consume(chunk)
      try await process(
        result,
        store: store,
        fileSize: fileSize,
        bytesRead: bytesRead,
        headers: &headers,
        pendingRows: &pendingRows,
        availableRowCount: &availableRowCount,
        continuation: continuation
      )
    }

    let finalResult = try streamingParser.finish()
    try await process(
      finalResult,
      store: store,
      fileSize: fileSize,
      bytesRead: bytesRead,
      headers: &headers,
      pendingRows: &pendingRows,
      availableRowCount: &availableRowCount,
      continuation: continuation
    )

    if !pendingRows.isEmpty {
      let page = try await store.append(pendingRows)
      availableRowCount += page.rows.count
      pendingRows.removeAll(keepingCapacity: false)
      continuation.yield(progress(
        headers: headers,
        rowCount: availableRowCount,
        bytesRead: bytesRead,
        fileSize: fileSize,
        isComplete: false
      ))
    }

    try await store.finish()
    continuation.yield(CSVLoadProgress(
      headers: headers,
      availableRowCount: availableRowCount,
      fractionCompleted: 1,
      isComplete: true
    ))
  }

  private func process(
    _ result: CSVParserChunkResult,
    store: any CSVPageStore,
    fileSize: Int,
    bytesRead: Int,
    headers: inout [String],
    pendingRows: inout [[String]],
    availableRowCount: inout Int,
    continuation: AsyncThrowingStream<CSVLoadProgress, Error>.Continuation
  ) async throws {
    if let emittedHeaders = result.headers {
      headers = emittedHeaders
      continuation.yield(progress(
        headers: headers,
        rowCount: availableRowCount,
        bytesRead: bytesRead,
        fileSize: fileSize,
        isComplete: false
      ))
    }

    pendingRows.append(contentsOf: result.rows)
    while pendingRows.count >= 500 {
      let rows = Array(pendingRows.prefix(500))
      pendingRows.removeFirst(500)
      let page = try await store.append(rows)
      availableRowCount += page.rows.count
      continuation.yield(progress(
        headers: headers,
        rowCount: availableRowCount,
        bytesRead: bytesRead,
        fileSize: fileSize,
        isComplete: false
      ))
    }
  }

  private func progress(
    headers: [String],
    rowCount: Int,
    bytesRead: Int,
    fileSize: Int,
    isComplete: Bool
  ) -> CSVLoadProgress {
    let fraction = fileSize > 0
      ? min(Double(bytesRead) / Double(fileSize), 1)
      : nil
    return CSVLoadProgress(
      headers: headers,
      availableRowCount: rowCount,
      fractionCompleted: fraction,
      isComplete: isComplete
    )
  }

  private func mapStreamingError(_ error: Error) -> Error {
    switch error {
    case CSVParserError.invalidUTF8:
      return CSVLoadingError.invalidEncoding
    case is CSVParserError:
      return CSVLoadingError.malformedCSV
    case is CSVPageStoreError:
      return CSVLoadingError.storageFailed
    default:
      return error
    }
  }

  private static func makeDefaultPageStore() throws -> any CSVPageStore {
    let cachesURL = try FileManager.default.url(
      for: .cachesDirectory,
      in: .userDomainMask,
      appropriateFor: nil,
      create: true
    )
    let directory = cachesURL
      .appendingPathComponent("CSVViewer", isDirectory: true)
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    return try FileBackedCSVPageStore(directoryURL: directory)
  }
}

private final class SessionTaskController: Sendable {
  private struct State {
    var task: Task<Void, Never>?
    var isCancelled = false
  }

  private let state = Mutex(State())

  func set(_ task: Task<Void, Never>) {
    let shouldCancel = state.withLock { state in
      if state.isCancelled { return true }
      state.task = task
      return false
    }
    if shouldCancel { task.cancel() }
  }

  func cancel() {
    let task = state.withLock { state in
      state.isCancelled = true
      return state.task
    }
    task?.cancel()
  }
}
