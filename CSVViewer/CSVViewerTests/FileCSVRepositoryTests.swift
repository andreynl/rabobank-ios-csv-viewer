import Foundation
import Testing
@testable import CSVViewer

struct FileCSVRepositoryTests {
  @Test func loadsAndParsesImportedFile() async throws {
    let url = try makeTemporaryFile(contents: Data("name,count\nTheo,5".utf8))
    defer { try? FileManager.default.removeItem(at: url) }
    let repository = FileCSVRepository(
      parser: CSVParser(),
      urlAccess: PassthroughSecurityScopedAccess()
    )

    let document = try await repository.load(from: .file(url))

    #expect(document == CSVDocument(headers: ["name", "count"], rows: [["Theo", "5"]]))
  }

  @Test func mapsMissingBundledResource() async {
    let repository = FileCSVRepository(
      parser: CSVParser(),
      urlAccess: PassthroughSecurityScopedAccess()
    )

    await expectLoadingError(.resourceNotFound) {
      try await repository.load(from: .bundled(name: UUID().uuidString, extension: "csv"))
    }
  }

  @Test func mapsInvalidEncoding() async throws {
    let url = try makeTemporaryFile(contents: Data([0xFF, 0xFE]))
    defer { try? FileManager.default.removeItem(at: url) }
    let repository = FileCSVRepository(
      parser: CSVParser(),
      urlAccess: PassthroughSecurityScopedAccess()
    )

    await expectLoadingError(.invalidEncoding) {
      try await repository.load(from: .file(url))
    }
  }

  @Test func mapsMalformedCSV() async throws {
    let url = try makeTemporaryFile(contents: Data("name,note\nTheo,\"unfinished".utf8))
    defer { try? FileManager.default.removeItem(at: url) }
    let repository = FileCSVRepository(
      parser: CSVParser(),
      urlAccess: PassthroughSecurityScopedAccess()
    )

    await expectLoadingError(.malformedCSV) {
      try await repository.load(from: .file(url))
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
