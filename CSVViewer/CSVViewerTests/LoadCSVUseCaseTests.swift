import Foundation
import Testing
@testable import CSVViewer

struct LoadCSVUseCaseTests {
  @Test func executeReturnsRepositoryDocument() async throws {
    let expectedDocument = CSVDocument(
      headers: ["Name", "Count"],
      rows: [["Theo", "5"]]
    )
    let repository = RepositoryStub(result: .success(expectedDocument))
    let useCase = LoadCSVUseCase(repository: repository)
    let source = CSVSource.file(URL(fileURLWithPath: "/tmp/issues.csv"))

    let document = try await useCase.execute(source: source)

    #expect(document == expectedDocument)
    #expect(await repository.receivedSources == [source])
  }

  @Test func executePropagatesRepositoryError() async {
    let repository = RepositoryStub(result: .failure(TestError.loadingFailed))
    let useCase = LoadCSVUseCase(repository: repository)

    do {
      _ = try await useCase.execute(source: .bundled(name: "issues", extension: "csv"))
      Issue.record("Expected repository error to be thrown")
    } catch {
      #expect(error as? TestError == .loadingFailed)
    }
  }
}

private enum TestError: Error, Equatable {
  case loadingFailed
}

private actor RepositoryStub: CSVRepository {
  private let result: Result<CSVDocument, Error>
  private(set) var receivedSources: [CSVSource] = []

  init(result: Result<CSVDocument, Error>) {
    self.result = result
  }

  func load(from source: CSVSource) async throws -> CSVDocument {
    receivedSources.append(source)
    return try result.get()
  }
}
