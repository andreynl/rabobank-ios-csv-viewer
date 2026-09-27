import Combine
import Foundation

@MainActor
final class CSVViewModel: ObservableObject {
  @Published private(set) var state: CSVViewState = .idle
  @Published private(set) var displayedFilename = ""

  private let loadCSV: any LoadCSVUseCaseProtocol
  private var loadingTask: Task<Void, Never>?
  private var hasRequestedBundledSample = false
  private var requestGeneration = 0

  init(loadCSV: any LoadCSVUseCaseProtocol) {
    self.loadCSV = loadCSV
  }

  func loadBundledSampleIfNeeded() {
    guard !hasRequestedBundledSample else { return }
    hasRequestedBundledSample = true
    load(source: .bundled(name: "issues", extension: "csv"), filename: "issues.csv")
  }

  func importFile(at url: URL) {
    load(source: .file(url), filename: url.lastPathComponent)
  }

  func handleImportFailure(_ error: Error) {
    requestGeneration += 1
    loadingTask?.cancel()
    state = .failure("The selected file could not be imported.")
  }

  private func load(source: CSVSource, filename: String) {
    requestGeneration += 1
    let generation = requestGeneration
    loadingTask?.cancel()
    displayedFilename = filename
    state = .loading

    loadingTask = Task { [loadCSV] in
      do {
        let document = try await loadCSV.execute(source: source)
        guard generation == requestGeneration else { return }
        state = document.headers.isEmpty ? .empty : .loaded(document)
      } catch is CancellationError {
        return
      } catch {
        guard generation == requestGeneration else { return }
        state = .failure(Self.message(for: error))
      }
    }
  }

  private static func message(for error: Error) -> String {
    switch error as? CSVLoadingError {
    case .resourceNotFound:
      return "The CSV file could not be found."
    case .accessDenied:
      return "Access to the selected file was denied."
    case .readFailed:
      return "The file could not be read."
    case .invalidEncoding:
      return "The file is not valid UTF-8 text."
    case .malformedCSV:
      return "The file contains malformed CSV data."
    case nil:
      return "The CSV file could not be loaded."
    }
  }
}
