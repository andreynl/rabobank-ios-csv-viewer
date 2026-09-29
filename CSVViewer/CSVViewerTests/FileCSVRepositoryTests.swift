import Foundation
import Testing
@testable import CSVViewer

struct FileCSVRepositoryTests {
  @Test func progressivelyLoadsSmallFileIntoPageStore() async throws {
    let url = try makeTemporaryFile(contents: Data("name,count\nTheo,5".utf8))
    let directory = temporaryDirectory()
    defer {
      try? FileManager.default.removeItem(at: url)
      try? FileManager.default.removeItem(at: directory)
    }
    let repository = FileCSVRepository(
      urlAccess: PassthroughSecurityScopedAccess(),
      pageStoreFactory: { try FileBackedCSVPageStore(directoryURL: directory) }
    )

    let session = try await repository.loadSession(from: .file(url))
    let updates = try await collect(session.updates)

    #expect(updates.last?.availableRowCount == 1)
    #expect(updates.last == CSVLoadProgress(
      headers: ["name", "count"],
      availableRowCount: 1,
      fractionCompleted: 1,
      isComplete: true
    ))
    #expect(try await session.pages.page(containing: 0).rows == [["Theo", "5"]])
  }

  @Test func publishesMonotonicProgressAcrossMultiplePages() async throws {
    let rows = (0..<501).map { "name-\($0),\($0)" }.joined(separator: "\n")
    let url = try makeTemporaryFile(contents: Data("name,count\n\(rows)".utf8))
    let directory = temporaryDirectory()
    defer {
      try? FileManager.default.removeItem(at: url)
      try? FileManager.default.removeItem(at: directory)
    }
    let repository = FileCSVRepository(
      urlAccess: PassthroughSecurityScopedAccess(),
      pageStoreFactory: { try FileBackedCSVPageStore(directoryURL: directory) }
    )

    let session = try await repository.loadSession(from: .file(url))
    let updates = try await collect(session.updates)

    #expect(updates.last?.availableRowCount == 501)
    #expect(zip(updates, updates.dropFirst()).allSatisfy { $0.availableRowCount <= $1.availableRowCount })
    #expect(updates.allSatisfy { progress in
      guard let fraction = progress.fractionCompleted else { return false }
      return (0...1).contains(fraction)
    })
    #expect(try await session.pages.page(containing: 500).rows == [["name-500", "500"]])
  }

  @Test func loadsRowsAcrossMultipleByteBoundedPages() async throws {
    let limits = CSVResourceLimits(
      maximumFieldBytes: 1_024,
      maximumRowBytes: 2_048,
      maximumPageBytes: 8 * 1_024
    )
    let rows = (0..<12).map { index in
      "\(index)-" + String(repeating: Character(UnicodeScalar(65 + index)!), count: 696)
    }
    let url = try makeTemporaryFile(contents: Data("value\n\(rows.joined(separator: "\n"))".utf8))
    let directory = temporaryDirectory()
    defer {
      try? FileManager.default.removeItem(at: url)
      try? FileManager.default.removeItem(at: directory)
    }
    let repository = FileCSVRepository(
      urlAccess: PassthroughSecurityScopedAccess(),
      limits: limits,
      pageStoreFactory: {
        try FileBackedCSVPageStore(
          directoryURL: directory,
          cacheCapacity: 1,
          maximumPageBytes: limits.maximumPageBytes
        )
      }
    )

    let session = try await repository.loadSession(from: .file(url))
    let updates = try await collect(session.updates)

    #expect(updates.last?.availableRowCount == rows.count)
    #expect(try await session.pages.page(containing: 11).rows.last == [rows[11]])
    #expect(try await session.pages.page(containing: 0).rows.first == [rows[0]])
  }

  @Test func headerOnlyFileCompletesWithoutPage() async throws {
    let url = try makeTemporaryFile(contents: Data("name,count".utf8))
    let directory = temporaryDirectory()
    defer {
      try? FileManager.default.removeItem(at: url)
      try? FileManager.default.removeItem(at: directory)
    }
    let repository = FileCSVRepository(
      urlAccess: PassthroughSecurityScopedAccess(),
      pageStoreFactory: { try FileBackedCSVPageStore(directoryURL: directory) }
    )

    let session = try await repository.loadSession(from: .file(url))
    let updates = try await collect(session.updates)

    #expect(updates.last?.availableRowCount == 0)
    #expect(updates.last?.isComplete == true)
    await #expect(throws: CSVPageStoreError.pageNotFound(0)) {
      try await session.pages.page(containing: 0)
    }
  }

  @Test func lateMalformedRowFailsAndCleansPartialPages() async throws {
    let validRows = Array(repeating: "Theo,5", count: 500).joined(separator: "\n")
    let csv = "name,count\n\(validRows)\nFiona,7,unexpected"
    let url = try makeTemporaryFile(contents: Data(csv.utf8))
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: url) }
    let repository = FileCSVRepository(
      urlAccess: PassthroughSecurityScopedAccess(),
      pageStoreFactory: { try FileBackedCSVPageStore(directoryURL: directory) }
    )

    let session = try await repository.loadSession(from: .file(url))

    do {
      _ = try await collect(session.updates)
      Issue.record("Expected malformed CSV failure")
    } catch {
      #expect(error as? CSVLoadingError == .malformedCSV)
    }
    #expect(!FileManager.default.fileExists(atPath: directory.path))
  }

  @Test func usesPageSizeExposedByStoreContract() async throws {
    let url = try makeTemporaryFile(contents: Data("name\na\nb\nc\nd\ne".utf8))
    let directory = temporaryDirectory()
    defer {
      try? FileManager.default.removeItem(at: url)
      try? FileManager.default.removeItem(at: directory)
    }
    let repository = FileCSVRepository(
      urlAccess: PassthroughSecurityScopedAccess(),
      pageStoreFactory: {
        try FileBackedCSVPageStore(directoryURL: directory, pageSize: 2)
      }
    )

    let session = try await repository.loadSession(from: .file(url))
    _ = try await collect(session.updates)

    #expect(session.pages.pageSize == 2)
    #expect(try await session.pages.page(containing: 3).index == 1)
    #expect(try await session.pages.page(containing: 4).rows == [["e"]])
  }

  @Test func keepsOnlyNewestProgressWhenConsumerStartsLate() async throws {
    let rows = (0..<1_501).map { "name-\($0)" }.joined(separator: "\n")
    let url = try makeTemporaryFile(contents: Data("name\n\(rows)".utf8))
    let directory = temporaryDirectory()
    defer {
      try? FileManager.default.removeItem(at: url)
      try? FileManager.default.removeItem(at: directory)
    }
    let repository = FileCSVRepository(
      urlAccess: PassthroughSecurityScopedAccess(),
      pageStoreFactory: { try FileBackedCSVPageStore(directoryURL: directory) }
    )

    let session = try await repository.loadSession(from: .file(url))
    try await Task.sleep(for: .milliseconds(50))
    let updates = try await collect(session.updates)

    #expect(updates == [CSVLoadProgress(
      headers: ["name"],
      availableRowCount: 1_501,
      fractionCompleted: 1,
      isComplete: true
    )])
  }

  @Test func mapsFileReadFailure() async throws {
    let repository = FileCSVRepository(urlAccess: PassthroughSecurityScopedAccess())
    let missingURL = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString)
    let session = try await repository.loadSession(from: .file(missingURL))

    await expectLoadingError(.readFailed) {
      try await collect(session.updates)
    }
  }

  @Test func mapsPageStoreCreationFailure() async {
    let repository = FileCSVRepository(
      urlAccess: PassthroughSecurityScopedAccess(),
      pageStoreFactory: { throw RepositoryTestError.expected }
    )

    await expectLoadingError(.storageFailed) {
      try await repository.loadSession(from: .file(URL(fileURLWithPath: "/tmp/file.csv")))
    }
  }

  @Test func cancellationReleasesSecurityScopedAccessAndClosesStore() async throws {
    let rows = Array(repeating: "Theo,5", count: 501).joined(separator: "\n")
    let url = try makeTemporaryFile(contents: Data("name,count\n\(rows)".utf8))
    defer { try? FileManager.default.removeItem(at: url) }
    let resourceAccessor = ResourceAccessorSpy(startResult: true)
    let store = BlockingPageStore()
    let repository = FileCSVRepository(
      urlAccess: SecurityScopedURLAccess(resourceAccessor: resourceAccessor),
      pageStoreFactory: { store }
    )

    let session = try await repository.loadSession(from: .file(url))
    var iterator = session.updates.makeAsyncIterator()
    #expect(try await iterator.next()?.headers == ["name", "count"])

    session.cancel()

    do {
      while try await iterator.next() != nil {}
    } catch is CancellationError {
      // Expected: cancelling the session interrupts the producer.
    }

    #expect(resourceAccessor.startedURLs == [url])
    #expect(resourceAccessor.stoppedURLs == [url])
    #expect(await store.isClosed)
  }

  @Test func mapsPageStoreFailureAndClosesStore() async throws {
    let rows = Array(repeating: "Theo,5", count: 500).joined(separator: "\n")
    let url = try makeTemporaryFile(contents: Data("name,count\n\(rows)".utf8))
    defer { try? FileManager.default.removeItem(at: url) }
    let store = FailingPageStore()
    let repository = FileCSVRepository(
      urlAccess: PassthroughSecurityScopedAccess(),
      pageStoreFactory: { store }
    )

    let session = try await repository.loadSession(from: .file(url))

    do {
      _ = try await collect(session.updates)
      Issue.record("Expected storage failure")
    } catch {
      #expect(error as? CSVLoadingError == .storageFailed)
    }
    #expect(await store.isClosed)
  }

  @Test func mapsMissingBundledResource() async {
    let repository = FileCSVRepository(
      urlAccess: PassthroughSecurityScopedAccess()
    )

    await expectLoadingError(.resourceNotFound) {
      try await repository.loadSession(from: .bundled(name: UUID().uuidString, extension: "csv"))
    }
  }

  @Test func mapsInvalidEncoding() async throws {
    let url = try makeTemporaryFile(contents: Data([0xFF, 0xFE]))
    defer { try? FileManager.default.removeItem(at: url) }
    let repository = FileCSVRepository(
      urlAccess: PassthroughSecurityScopedAccess()
    )

    let session = try await repository.loadSession(from: .file(url))
    await expectLoadingError(.invalidEncoding) {
      try await collect(session.updates)
    }
  }

  @Test func mapsMalformedCSV() async throws {
    let url = try makeTemporaryFile(contents: Data("name,note\nTheo,\"unfinished".utf8))
    defer { try? FileManager.default.removeItem(at: url) }
    let repository = FileCSVRepository(
      urlAccess: PassthroughSecurityScopedAccess()
    )

    let session = try await repository.loadSession(from: .file(url))
    await expectLoadingError(.malformedCSV) {
      try await collect(session.updates)
    }
  }

  @Test func mapsFieldByteLimitFailure() async throws {
    let url = try makeTemporaryFile(contents: Data("name\nabcde".utf8))
    defer { try? FileManager.default.removeItem(at: url) }
    let repository = FileCSVRepository(
      urlAccess: PassthroughSecurityScopedAccess(),
      limits: CSVResourceLimits(
        maximumFieldBytes: 4,
        maximumRowBytes: 16,
        maximumPageBytes: 32
      )
    )

    let session = try await repository.loadSession(from: .file(url))
    await expectLoadingError(.resourceLimitExceeded) {
      try await collect(session.updates)
    }
  }

  @Test func mapsRowByteLimitFailure() async throws {
    let url = try makeTemporaryFile(contents: Data("a,b\nx,y,z".utf8))
    defer { try? FileManager.default.removeItem(at: url) }
    let repository = FileCSVRepository(
      urlAccess: PassthroughSecurityScopedAccess(),
      limits: CSVResourceLimits(
        maximumFieldBytes: 2,
        maximumRowBytes: 4,
        maximumPageBytes: 8
      )
    )

    let session = try await repository.loadSession(from: .file(url))
    await expectLoadingError(.resourceLimitExceeded) {
      try await collect(session.updates)
    }
  }

  @Test func mapsEncodedPageLimitFailure() async throws {
    let url = try makeTemporaryFile(contents: Data("name\nTheo".utf8))
    defer { try? FileManager.default.removeItem(at: url) }
    let repository = FileCSVRepository(
      urlAccess: PassthroughSecurityScopedAccess(),
      pageStoreFactory: { ResourceLimitedPageStore() }
    )

    let session = try await repository.loadSession(from: .file(url))
    await expectLoadingError(.resourceLimitExceeded) {
      try await collect(session.updates)
    }
  }

  @Test func releasesSecurityScopedAccessAfterSuccess() async throws {
    let resourceAccessor = ResourceAccessorSpy(startResult: true)
    let access = SecurityScopedURLAccess(resourceAccessor: resourceAccessor)
    let url = URL(fileURLWithPath: "/tmp/example.csv")

    let result = try await access.withAccess(to: url) { _ in "loaded" }

    #expect(result == "loaded")
    #expect(resourceAccessor.startedURLs == [url])
    #expect(resourceAccessor.stoppedURLs == [url])
  }

  @Test func releasesSecurityScopedAccessAfterFailure() async {
    let resourceAccessor = ResourceAccessorSpy(startResult: true)
    let access = SecurityScopedURLAccess(resourceAccessor: resourceAccessor)
    let url = URL(fileURLWithPath: "/tmp/example.csv")

    do {
      _ = try await access.withAccess(to: url) { _ -> String in
        throw RepositoryTestError.expected
      }
      Issue.record("Expected operation error")
    } catch {
      #expect(error as? RepositoryTestError == .expected)
    }

    #expect(resourceAccessor.startedURLs == [url])
    #expect(resourceAccessor.stoppedURLs == [url])
  }

  @Test func reportsDeniedSecurityScopedAccess() async {
    let access = SecurityScopedURLAccess(resourceAccessor: ResourceAccessorSpy(startResult: false))

    await expectLoadingError(.accessDenied) {
      try await access.withAccess(to: URL(fileURLWithPath: "/tmp/example.csv")) { _ in "unused" }
    }
  }

  private func makeTemporaryFile(contents: Data) throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try contents.write(to: url)
    return url
  }

  private func temporaryDirectory() -> URL {
    FileManager.default.temporaryDirectory
      .appendingPathComponent("FileCSVRepositoryTests-\(UUID().uuidString)", isDirectory: true)
  }

  private func collect(
    _ stream: AsyncThrowingStream<CSVLoadProgress, Error>
  ) async throws -> [CSVLoadProgress] {
    var values: [CSVLoadProgress] = []
    for try await value in stream {
      values.append(value)
    }
    return values
  }

  private func expectLoadingError(
    _ expectedError: CSVLoadingError,
    operation: () async throws -> some Sendable
  ) async {
    do {
      _ = try await operation()
      Issue.record("Expected \(expectedError) to be thrown")
    } catch {
      #expect(error as? CSVLoadingError == expectedError)
    }
  }
}

private enum RepositoryTestError: Error, Equatable {
  case expected
}

private struct PassthroughSecurityScopedAccess: SecurityScopedURLAccessing {
  func withAccess<T: Sendable>(
    to url: URL,
    operation: @Sendable (URL) async throws -> T
  ) async throws -> T {
    try await operation(url)
  }
}

private final class ResourceAccessorSpy: URLResourceAccessing, @unchecked Sendable {
  private let lock = NSLock()
  private let startResult: Bool
  private var _startedURLs: [URL] = []
  private var _stoppedURLs: [URL] = []

  init(startResult: Bool) {
    self.startResult = startResult
  }

  var startedURLs: [URL] {
    lock.withLock { _startedURLs }
  }

  var stoppedURLs: [URL] {
    lock.withLock { _stoppedURLs }
  }

  func startAccessing(_ url: URL) -> Bool {
    lock.withLock { _startedURLs.append(url) }
    return startResult
  }

  func stopAccessing(_ url: URL) {
    lock.withLock { _stoppedURLs.append(url) }
  }
}

private actor BlockingPageStore: CSVPageStore {
  nonisolated let pageSize = CSVPageConfiguration.defaultPageSize
  private(set) var isClosed = false

  func append(_ rows: [[String]]) async throws -> CSVRowPage {
    try await Task.sleep(for: .seconds(30))
    return CSVRowPage(index: 0, startRow: 0, rows: rows)
  }

  func finish() async throws {}

  func page(containing rowIndex: Int) async throws -> CSVRowPage {
    throw CSVPageStoreError.pageNotFound(rowIndex)
  }

  func close() async {
    isClosed = true
  }
}

private actor ResourceLimitedPageStore: CSVPageStore {
  nonisolated let pageSize = CSVPageConfiguration.defaultPageSize

  func append(_ rows: [[String]]) async throws -> CSVRowPage {
    throw CSVPageStoreError.encodedPageTooLarge(maximumBytes: 8, actualBytes: 9)
  }

  func finish() async throws {}

  func page(containing rowIndex: Int) async throws -> CSVRowPage {
    throw CSVPageStoreError.pageNotFound(rowIndex)
  }

  func close() async {}
}

private actor FailingPageStore: CSVPageStore {
  nonisolated let pageSize = CSVPageConfiguration.defaultPageSize
  private(set) var isClosed = false

  func append(_ rows: [[String]]) async throws -> CSVRowPage {
    throw CSVPageStoreError.invalidPage(0)
  }

  func finish() async throws {}

  func page(containing rowIndex: Int) async throws -> CSVRowPage {
    throw CSVPageStoreError.pageNotFound(rowIndex)
  }

  func close() async {
    isClosed = true
  }
}
