import Foundation
import Testing
@testable import CSVViewer

struct LoadPagedCSVUseCaseTests {
  @Test func executeReturnsRepositorySession() async throws {
    let session = makeSession()
    let repository = PagedRepositoryStub(result: .success(session))
    let useCase = LoadPagedCSVUseCase(repository: repository)
    let source = CSVSource.file(URL(fileURLWithPath: "/tmp/issues.csv"))

    let receivedSession = try await useCase.execute(source: source)

    #expect(receivedSession === session)
    #expect(await repository.receivedSources == [source])
  }

  @Test func executePropagatesRepositoryError() async {
    let repository = PagedRepositoryStub(result: .failure(PagedUseCaseTestError.loadingFailed))
    let useCase = LoadPagedCSVUseCase(repository: repository)

    do {
      _ = try await useCase.execute(source: .bundled(name: "issues", extension: "csv"))
      Issue.record("Expected repository error to be thrown")
    } catch {
      #expect(error as? PagedUseCaseTestError == .loadingFailed)
    }
  }

  private func makeSession() -> CSVLoadSession {
    CSVLoadSession(
      updates: AsyncThrowingStream { $0.finish() },
      pages: EmptyPageProvider(),
      onCancel: {}
    )
  }
}

private enum PagedUseCaseTestError: Error, Equatable {
  case loadingFailed
}

private actor PagedRepositoryStub: PagedCSVRepository {
  private let result: Result<CSVLoadSession, Error>
  private(set) var receivedSources: [CSVSource] = []

  init(result: Result<CSVLoadSession, Error>) {
    self.result = result
  }

  func loadSession(from source: CSVSource) async throws -> CSVLoadSession {
    receivedSources.append(source)
    return try result.get()
  }
}

private actor EmptyPageProvider: CSVPageProviding {
  nonisolated let pageSize = CSVPageConfiguration.defaultPageSize
  func page(containing rowIndex: Int) async throws -> CSVRowPage {
    throw CSVPageStoreError.pageNotFound(rowIndex)
  }

  func close() async {}
}
