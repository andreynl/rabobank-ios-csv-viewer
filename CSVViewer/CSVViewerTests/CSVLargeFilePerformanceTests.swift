import Foundation
import Synchronization
import XCTest
@testable import CSVViewer

final class CSVLargeFilePerformanceTests: XCTestCase {
  func testFiftyMegabyteCSVPerformance() throws {
    #if RUN_LARGE_CSV_PERFORMANCE_TEST
    let fixture = try makeLargeFixture(minimumSize: 50 * 1024 * 1024)
    defer { try? FileManager.default.removeItem(at: fixture.directoryURL) }

    let result = Mutex<Result<PerformanceResult, PerformanceTestFailure>?>(nil)
    let options = XCTMeasureOptions()
    options.iterationCount = 1

    measure(
      metrics: [XCTClockMetric(), XCTMemoryMetric()],
      options: options
    ) {
      let completion = expectation(description: "Large CSV processing completed")
      Task.detached {
        var stage = "create page store"
        do {
          let pageDirectoryURL = fixture.directoryURL
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
          let store = try FileBackedCSVPageStore(
            directoryURL: pageDirectoryURL,
            cacheCapacity: 5
          )
          let repository = FileCSVRepository(
            urlAccess: PerformanceURLAccess(),
            pageStoreFactory: { store }
          )
          stage = "create session"
          let session = try await repository.loadSession(from: .file(fixture.fileURL))
          stage = "consume progress stream"
          var finalProgress: CSVLoadProgress?
          for try await progress in session.updates {
            finalProgress = progress
          }

          let sampleIndexes = [0, fixture.rowCount / 2, fixture.rowCount - 1]
          var sampledRows: [Int: [String]] = [:]
          for rowIndex in sampleIndexes {
            stage = "load sample row \(rowIndex)"
            let page = try await session.pages.page(containing: rowIndex)
            sampledRows[rowIndex] = page.rows[rowIndex - page.startRow]
          }
          let cachedPageCount = await store.cachedPageIndexes.count
          session.cancel()
          await session.pages.close()

          result.withLock {
            $0 = .success(PerformanceResult(
              finalProgress: finalProgress,
              sampledRows: sampledRows,
              cachedPageCount: cachedPageCount,
              removedPageDirectory: !FileManager.default.fileExists(atPath: pageDirectoryURL.path)
            ))
          }
        } catch {
          result.withLock {
            $0 = .failure(PerformanceTestFailure(
              stage: stage,
              underlying: String(reflecting: error)
            ))
          }
        }
        completion.fulfill()
      }
      wait(for: [completion], timeout: 180)
    }

    let performanceResult = try XCTUnwrap(result.withLock { $0 }).get()
    XCTAssertEqual(performanceResult.finalProgress?.availableRowCount, fixture.rowCount)
    XCTAssertEqual(performanceResult.finalProgress?.fractionCompleted, 1)
    XCTAssertEqual(performanceResult.finalProgress?.isComplete, true)
    XCTAssertLessThanOrEqual(performanceResult.cachedPageCount, 5)
    XCTAssertTrue(performanceResult.removedPageDirectory)

    for rowIndex in [0, fixture.rowCount / 2, fixture.rowCount - 1] {
      XCTAssertEqual(performanceResult.sampledRows[rowIndex], expectedRow(at: rowIndex))
    }
    #else
    throw XCTSkip(
      "Add RUN_LARGE_CSV_PERFORMANCE_TEST to Swift compilation conditions to run this exercise."
    )
    #endif
  }

  private func makeLargeFixture(minimumSize: Int) throws -> LargeFixture {
    let directoryURL = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    let fileURL = directoryURL.appendingPathComponent("performance.csv")
    _ = FileManager.default.createFile(atPath: fileURL.path, contents: nil)
    let handle = try FileHandle(forWritingTo: fileURL)
    defer { try? handle.close() }

    let header = Data("row_id,first_name,surname,issue_count,date_of_birth,payload\n".utf8)
    try handle.write(contentsOf: header)
    var writtenBytes = header.count
    var rowIndex = 0

    while writtenBytes <= minimumSize {
      var chunk = Data()
      while chunk.count < 1024 * 1024 {
        chunk.append(Data(rowString(at: rowIndex).utf8))
        rowIndex += 1
      }
      try handle.write(contentsOf: chunk)
      writtenBytes += chunk.count
    }

    return LargeFixture(
      directoryURL: directoryURL,
      fileURL: fileURL,
      rowCount: rowIndex
    )
  }

  private func rowString(at index: Int) -> String {
    let paddedIndex = String(format: "%08d", index)
    return "\(paddedIndex),Name\(paddedIndex),Surname\(paddedIndex),\(index % 100),2000-01-01T00:00:00,abcdefghijklmnopqrstuvwxyz0123456789\n"
  }

  private func expectedRow(at index: Int) -> [String] {
    let paddedIndex = String(format: "%08d", index)
    return [
      paddedIndex,
      "Name\(paddedIndex)",
      "Surname\(paddedIndex)",
      String(index % 100),
      "2000-01-01T00:00:00",
      "abcdefghijklmnopqrstuvwxyz0123456789",
    ]
  }
}

private struct LargeFixture: Sendable {
  let directoryURL: URL
  let fileURL: URL
  let rowCount: Int
}

private struct PerformanceResult: Sendable {
  let finalProgress: CSVLoadProgress?
  let sampledRows: [Int: [String]]
  let cachedPageCount: Int
  let removedPageDirectory: Bool
}

private struct PerformanceTestFailure: Error, LocalizedError, Sendable {
  let stage: String
  let underlying: String

  var errorDescription: String? {
    "Performance exercise failed during \(stage): \(underlying)"
  }
}

private struct PerformanceURLAccess: SecurityScopedURLAccessing {
  func withAccess<T: Sendable>(
    to url: URL,
    operation: @Sendable (URL) async throws -> T
  ) async throws -> T {
    try await operation(url)
  }
}
