import Synchronization
import Testing
@testable import CSVViewer

struct CSVLoadSessionTests {
  @Test func exposesProgressAndPageProvider() async throws {
    let expectedProgress = CSVLoadProgress(
      headers: ["Name", "Count"],
      availableRowCount: 1,
      fractionCompleted: 0.5,
      isComplete: false
    )
    let expectedPage = CSVRowPage(
      index: 0,
      startRow: 0,
      rows: [["Theo", "5"]]
    )
    let provider = PageProviderStub(page: expectedPage)
    let updates = AsyncThrowingStream<CSVLoadProgress, Error> { continuation in
      continuation.yield(expectedProgress)
      continuation.finish()
    }
    let session = CSVLoadSession(
      updates: updates,
      pages: provider,
      onCancel: {}
    )

    var iterator = session.updates.makeAsyncIterator()

    #expect(try await iterator.next() == expectedProgress)
    #expect(try await session.pages.page(containing: 0) == expectedPage)
  }

  @Test func cancellationIsIdempotentAndRunsOnRelease() {
    let explicitCancellationCount = Mutex(0)
    var explicitSession: CSVLoadSession? = makeSession {
      explicitCancellationCount.withLock { $0 += 1 }
    }

    explicitSession?.cancel()
    explicitSession?.cancel()
    explicitSession = nil

    #expect(explicitCancellationCount.withLock { $0 } == 1)

    let releaseCancellationCount = Mutex(0)
    var releasedSession: CSVLoadSession? = makeSession {
      releaseCancellationCount.withLock { $0 += 1 }
    }

    #expect(releasedSession != nil)
    releasedSession = nil

    #expect(releaseCancellationCount.withLock { $0 } == 1)
  }

  private func makeSession(onCancel: @escaping @Sendable () -> Void) -> CSVLoadSession {
    CSVLoadSession(
      updates: AsyncThrowingStream { $0.finish() },
      pages: PageProviderStub(
        page: CSVRowPage(index: 0, startRow: 0, rows: [])
      ),
      onCancel: onCancel
    )
  }
}

private actor PageProviderStub: CSVPageProviding {
  nonisolated let pageSize = CSVPageConfiguration.defaultPageSize
  private let page: CSVRowPage

  init(page: CSVRowPage) {
    self.page = page
  }

  func page(containing rowIndex: Int) async throws -> CSVRowPage {
    page
  }

  func close() async {}
}
