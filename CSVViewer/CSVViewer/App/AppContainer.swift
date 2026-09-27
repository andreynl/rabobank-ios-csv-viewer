@MainActor
struct AppContainer {
  func makeCSVViewModel() -> CSVViewModel {
    let parser = CSVParser()
    let urlAccess = SecurityScopedURLAccess()
    let repository = FileCSVRepository(parser: parser, urlAccess: urlAccess)
    let useCase = LoadCSVUseCase(repository: repository)
    return CSVViewModel(loadCSV: useCase)
  }
}
