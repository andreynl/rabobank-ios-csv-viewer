import Testing
@testable import CSVViewer

@MainActor
struct AppContainerTests {
  @Test func composedViewModelLoadsBundledIssuesFile() async {
    let viewModel = AppContainer().makeCSVViewModel()

    viewModel.loadBundledSampleIfNeeded()
    for _ in 0..<1_000 {
      if case .loaded = viewModel.state { break }
      if case let .failure(message) = viewModel.state {
        Issue.record("Unexpected load failure: \(message)")
        return
      }
      await Task.yield()
    }

    guard case let .loaded(document) = viewModel.state else {
      Issue.record("Expected a loaded document")
      return
    }
    #expect(document.headers == ["First name", "Sur name", "Issue count", "Date of birth"])
    #expect(!document.rows.isEmpty)
    #expect(document.rows.first == ["Theo", "Jansen", "5", "1978-01-02T00:00:00"])
  }
}
