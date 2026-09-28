protocol LoadPagedCSVUseCaseProtocol: Sendable {
  func execute(source: CSVSource) async throws -> CSVLoadSession
}

struct LoadPagedCSVUseCase: LoadPagedCSVUseCaseProtocol, Sendable {
  private let repository: any PagedCSVRepository

  init(repository: any PagedCSVRepository) {
    self.repository = repository
  }

  func execute(source: CSVSource) async throws -> CSVLoadSession {
    try await repository.loadSession(from: source)
  }
}
