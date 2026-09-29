import Foundation

@MainActor
struct AppContainer {
  func makeCSVViewModel() -> CSVViewModel {
    #if DEBUG
    if ProcessInfo.processInfo.arguments.contains("-UITestForceCSVLoadFailure") {
      return CSVViewModel(loadCSV: UITestFailingLoadUseCase())
    }
    #endif
    let urlAccess = SecurityScopedURLAccess()
    let repository = FileCSVRepository(urlAccess: urlAccess)
    let useCase = LoadPagedCSVUseCase(repository: repository)
    return CSVViewModel(loadCSV: useCase)
  }
}

#if DEBUG
private actor UITestFailingLoadUseCase: LoadPagedCSVUseCaseProtocol {
  private var attempt = 0

  func execute(source: CSVSource) async throws -> CSVLoadSession {
    attempt += 1
    if attempt > 1 {
      try await Task.sleep(for: .seconds(2))
    }
    throw CSVLoadingError.readFailed
  }
}
#endif
