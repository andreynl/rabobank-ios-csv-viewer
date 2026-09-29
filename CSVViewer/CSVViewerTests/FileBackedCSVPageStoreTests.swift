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
    #expect(throws: CSVPageStoreError.invalidConfiguration) {
      try FileBackedCSVPageStore(directoryURL: temporaryDirectory(), maximumPageBytes: 0)
    }
  }

  @Test func persistsPageWithinEncodedByteLimit() async throws {
    let directory = temporaryDirectory()
    let store = try FileBackedCSVPageStore(
      directoryURL: directory,
      maximumPageBytes: 1_024
    )
    defer { try? FileManager.default.removeItem(at: directory) }

    let page = try await store.append([["small", "row"]])

    #expect(page.index == 0)
    #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).count == 1)
  }

  @Test func rejectsOversizedEncodedPageWithoutAdvancingStore() async throws {
    let directory = temporaryDirectory()
    let store = try FileBackedCSVPageStore(
      directoryURL: directory,
      maximumPageBytes: 256
    )
    defer { try? FileManager.default.removeItem(at: directory) }

    do {
      _ = try await store.append([[String(repeating: "x", count: 1_024)]])
      Issue.record("Expected encoded page limit failure")
    } catch let CSVPageStoreError.encodedPageTooLarge(maximumBytes, actualBytes) {
      #expect(maximumBytes == 256)
      #expect(actualBytes > maximumBytes)
    } catch {
      Issue.record("Unexpected error: \(error)")
    }

    #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
    let firstValidPage = try await store.append([["ok"]])
    #expect(firstValidPage.index == 0)
    #expect(firstValidPage.startRow == 0)
  }

  @Test func persistsFullAndPartialPagesWithStableRanges() async throws {
    let directory = temporaryDirectory()
    let store = try FileBackedCSVPageStore(directoryURL: directory, cacheCapacity: 0)
    defer { try? FileManager.default.removeItem(at: directory) }

    let firstRows = (0..<500).map { ["row-\($0)"] }
    let secondRows = (500..<507).map { ["row-\($0)"] }

    let first = try await store.append(firstRows)
    let second = try await store.append(secondRows)
    try await store.finish()

    #expect(first == CSVRowPage(index: 0, startRow: 0, rows: firstRows))
    #expect(second == CSVRowPage(index: 1, startRow: 500, rows: secondRows))

    #expect(try await store.page(containing: 503) == second)
  }

  @Test func supportsMultipleVariableLengthPagesAndReloadsTheirRanges() async throws {
    let directory = temporaryDirectory()
    let store = try FileBackedCSVPageStore(
      directoryURL: directory,
      pageSize: 5,
      cacheCapacity: 1
    )
    defer { try? FileManager.default.removeItem(at: directory) }

    let first = try await store.append([["row-0"], ["row-1"]])
    let second = try await store.append([["row-2"], ["row-3"], ["row-4"]])

    #expect(first.startRow == 0)
    #expect(second.startRow == 2)
    #expect(try await store.page(containing: 4) == second)
    #expect(try await store.page(containing: 1) == first)

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
