protocol LoadCSVUseCaseProtocol: Sendable {
  func execute(source: CSVSource) async throws -> CSVDocument
}

struct LoadCSVUseCase: LoadCSVUseCaseProtocol, Sendable {
  private let repository: any CSVRepository

  init(repository: any CSVRepository) {
    self.repository = repository
  }

  func execute(source: CSVSource) async throws -> CSVDocument {
    try await repository.load(from: source)
  }
}
