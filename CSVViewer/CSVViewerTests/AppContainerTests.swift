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

    guard case .loaded = viewModel.state else {
      Issue.record("Expected a loaded document")
      return
    }
    #expect(viewModel.headers == ["First name", "Sur name", "Issue count", "Date of birth"])
    #expect(viewModel.availableRowCount > 0)
    await viewModel.loadPage(containing: 0)
    #expect(viewModel.row(at: 0) == ["Theo", "Jansen", "5", "1978-01-02T00:00:00"])
  }
}
