import Foundation
import Testing
@testable import CSVViewer

@MainActor
struct CSVViewModelTests {
  @Test func loadsBundledDocumentThroughExpectedStates() async {
    let useCase = ControllableLoadCSVUseCase()
    let viewModel = CSVViewModel(loadCSV: useCase)
    let source = CSVSource.bundled(name: "issues", extension: "csv")
    let document = CSVDocument(headers: ["name"], rows: [["Theo"]])

    viewModel.loadBundledSampleIfNeeded()
    #expect(viewModel.state == .loading)
    await useCase.waitUntilRequested(source)
    await useCase.succeed(source, with: document)
    await waitUntil { viewModel.state == .loaded(document) }

    #expect(viewModel.displayedFilename == "issues.csv")
  }

  @Test func emptyDocumentUsesEmptyState() async {
    let useCase = ControllableLoadCSVUseCase()
    let viewModel = CSVViewModel(loadCSV: useCase)
    let source = CSVSource.bundled(name: "issues", extension: "csv")

    viewModel.loadBundledSampleIfNeeded()
    await useCase.waitUntilRequested(source)
    await useCase.succeed(source, with: CSVDocument(headers: [], rows: []))

    await waitUntil { viewModel.state == .empty }
  }

  @Test func headerOnlyDocumentUsesLoadedState() async {
    let useCase = ControllableLoadCSVUseCase()
    let viewModel = CSVViewModel(loadCSV: useCase)
    let source = CSVSource.bundled(name: "issues", extension: "csv")
    let document = CSVDocument(headers: ["name"], rows: [])

    viewModel.loadBundledSampleIfNeeded()
    await useCase.waitUntilRequested(source)
    await useCase.succeed(source, with: document)

    await waitUntil { viewModel.state == .loaded(document) }
  }

  @Test func loadingFailureUsesReadableFailureState() async {
    let useCase = ControllableLoadCSVUseCase()
    let viewModel = CSVViewModel(loadCSV: useCase)
    let source = CSVSource.bundled(name: "issues", extension: "csv")

    viewModel.loadBundledSampleIfNeeded()
    await useCase.waitUntilRequested(source)
    await useCase.fail(source, with: CSVLoadingError.readFailed)

    await waitUntil { viewModel.state == .failure("The file could not be read.") }
  }

  @Test func bundledSampleLoadsOnlyOnce() async {
    let useCase = ControllableLoadCSVUseCase()
    let viewModel = CSVViewModel(loadCSV: useCase)
    let source = CSVSource.bundled(name: "issues", extension: "csv")

    viewModel.loadBundledSampleIfNeeded()
    viewModel.loadBundledSampleIfNeeded()
    await useCase.waitUntilRequested(source)

    #expect(await useCase.requestCount(for: source) == 1)
    await useCase.succeed(source, with: CSVDocument(headers: ["name"], rows: []))
  }

  @Test func importedFileReplacesCurrentDocumentAndFilename() async {
    let useCase = ControllableLoadCSVUseCase()
    let viewModel = CSVViewModel(loadCSV: useCase)
    let url = URL(fileURLWithPath: "/tmp/replacement.csv")
    let source = CSVSource.file(url)
    let document = CSVDocument(headers: ["replacement"], rows: [["value"]])

    viewModel.importFile(at: url)
    #expect(viewModel.state == .loading)
    await useCase.waitUntilRequested(source)
    await useCase.succeed(source, with: document)
    await waitUntil { viewModel.state == .loaded(document) }

    #expect(viewModel.displayedFilename == "replacement.csv")
  }

  @Test func staleBundledResultCannotOverwriteNewerImport() async {
    let useCase = ControllableLoadCSVUseCase()
    let viewModel = CSVViewModel(loadCSV: useCase)
    let bundled = CSVSource.bundled(name: "issues", extension: "csv")
    let importedURL = URL(fileURLWithPath: "/tmp/new.csv")
    let imported = CSVSource.file(importedURL)
    let importedDocument = CSVDocument(headers: ["new"], rows: [["data"]])

    viewModel.loadBundledSampleIfNeeded()
    await useCase.waitUntilRequested(bundled)
    viewModel.importFile(at: importedURL)
    await useCase.waitUntilRequested(imported)
    await useCase.succeed(imported, with: importedDocument)
    await waitUntil { viewModel.state == .loaded(importedDocument) }

    await useCase.succeed(bundled, with: CSVDocument(headers: ["old"], rows: [["stale"]]))
    await Task.yield()

    #expect(viewModel.state == .loaded(importedDocument))
    #expect(viewModel.displayedFilename == "new.csv")
  }

  private func waitUntil(
    _ predicate: @escaping @MainActor () -> Bool
  ) async {
    for _ in 0..<1_000 {
      if predicate() { return }
      await Task.yield()
    }
    Issue.record("Condition was not met")
  }
}

private actor ControllableLoadCSVUseCase: LoadCSVUseCaseProtocol {
  private struct Request {
    let source: CSVSource
    let continuation: CheckedContinuation<CSVDocument, Error>
  }

  private var requests: [Request] = []
  private var receivedSources: [CSVSource] = []

  func execute(source: CSVSource) async throws -> CSVDocument {
    receivedSources.append(source)
    return try await withCheckedThrowingContinuation { continuation in
      requests.append(Request(source: source, continuation: continuation))
    }
  }

  func waitUntilRequested(_ source: CSVSource) async {
    for _ in 0..<1_000 {
      if receivedSources.contains(source) { return }
      await Task.yield()
    }
    Issue.record("Expected request for \(source)")
  }

  func requestCount(for source: CSVSource) -> Int {
    receivedSources.filter { $0 == source }.count
  }

  func succeed(_ source: CSVSource, with document: CSVDocument) {
    resume(source, with: .success(document))
  }

  func fail(_ source: CSVSource, with error: Error) {
    resume(source, with: .failure(error))
  }

  private func resume(_ source: CSVSource, with result: Result<CSVDocument, Error>) {
    guard let index = requests.firstIndex(where: { $0.source == source }) else {
      Issue.record("No pending request for \(source)")
      return
    }
    let request = requests.remove(at: index)
    request.continuation.resume(with: result)
  }
}
