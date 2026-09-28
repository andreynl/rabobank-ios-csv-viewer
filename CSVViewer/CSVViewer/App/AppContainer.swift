@MainActor
struct AppContainer {
  func makeCSVViewModel() -> CSVViewModel {
    let urlAccess = SecurityScopedURLAccess()
    let repository = FileCSVRepository(urlAccess: urlAccess)
    let useCase = LoadPagedCSVUseCase(repository: repository)
    return CSVViewModel(loadCSV: useCase)
  }
}
