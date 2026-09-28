import Foundation
import Testing
@testable import CSVViewer

struct FileBackedCSVPageStoreTests {
  @Test func rejectsInvalidConfiguration() {
    #expect(throws: CSVPageStoreError.invalidConfiguration) {
      try FileBackedCSVPageStore(directoryURL: temporaryDirectory(), pageSize: 0)
    }
    #expect(throws: CSVPageStoreError.invalidConfiguration) {
      try FileBackedCSVPageStore(directoryURL: temporaryDirectory(), cacheCapacity: -1)
    }
  }

  @Test func persistsFullAndPartialPagesWithStableRanges() async throws {
    let directory = temporaryDirectory()
    let store = try FileBackedCSVPageStore(directoryURL: directory)
    defer { try? FileManager.default.removeItem(at: directory) }

    let firstRows = (0..<500).map { ["row-\($0)"] }
    let secondRows = (500..<507).map { ["row-\($0)"] }

    let first = try await store.append(firstRows)
    let second = try await store.append(secondRows)
    try await store.finish()

    #expect(first == CSVRowPage(index: 0, startRow: 0, rows: firstRows))
    #expect(second == CSVRowPage(index: 1, startRow: 500, rows: secondRows))

    let reader = try FileBackedCSVPageStore(directoryURL: directory)
    #expect(try await reader.page(containing: 503) == second)
  }

  @Test func evictsLeastRecentlyUsedPageAndReloadsItFromDisk() async throws {
    let directory = temporaryDirectory()
    let store = try FileBackedCSVPageStore(directoryURL: directory, cacheCapacity: 5)
    defer { try? FileManager.default.removeItem(at: directory) }

    for pageIndex in 0..<6 {
      _ = try await store.append(
        Array(repeating: ["page-\(pageIndex)"], count: 500)
      )
    }

    #expect(await store.cachedPageIndexes == [1, 2, 3, 4, 5])
    let reloadedPage = try await store.page(containing: 0)
    #expect(reloadedPage.rows.count == 500)
    #expect(reloadedPage.rows.first == ["page-0"])
    #expect(await store.cachedPageIndexes == [2, 3, 4, 5, 0])
  }

  @Test func closeRemovesSessionDirectoryAndIsIdempotent() async throws {
    let directory = temporaryDirectory()
    let store = try FileBackedCSVPageStore(directoryURL: directory)
    _ = try await store.append([["value"]])

    await store.close()
    await store.close()

    #expect(!FileManager.default.fileExists(atPath: directory.path))
  }

  @Test func cancelledAppendDoesNotPublishPartialPage() async throws {
    let directory = temporaryDirectory()
    let store = try FileBackedCSVPageStore(directoryURL: directory)
    defer { try? FileManager.default.removeItem(at: directory) }

    let task = Task {
      withUnsafeCurrentTask { $0?.cancel() }
      return try await store.append([["cancelled"]])
    }

    do {
      _ = try await task.value
      Issue.record("Expected cancellation")
    } catch is CancellationError {
      // Expected.
    }

    #expect(await store.cachedPageIndexes.isEmpty)
    #expect((try FileManager.default.contentsOfDirectory(atPath: directory.path)).isEmpty)
  }

  @Test func rejectsEmptyAndOversizedBatches() async throws {
    let directory = temporaryDirectory()
    let store = try FileBackedCSVPageStore(directoryURL: directory)
    defer { try? FileManager.default.removeItem(at: directory) }

    await #expect(throws: CSVPageStoreError.emptyPage) {
      try await store.append([])
    }
    await #expect(throws: CSVPageStoreError.pageTooLarge(maximum: 500, actual: 501)) {
      try await store.append(Array(repeating: ["row"], count: 501))
    }
  }

  private func temporaryDirectory() -> URL {
    FileManager.default.temporaryDirectory
      .appendingPathComponent("CSVPageStoreTests-\(UUID().uuidString)", isDirectory: true)
  }
}
