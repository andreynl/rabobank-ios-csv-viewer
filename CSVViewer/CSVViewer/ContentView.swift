import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
  private let viewModel: CSVViewModel
  @State private var isImporterPresented = false

  init(viewModel: CSVViewModel) {
    self.viewModel = viewModel
  }

  var body: some View {
    NavigationStack {
      Group {
        switch viewModel.state {
        case .idle, .loading:
          ProgressView("Loading CSV…")
            .accessibilityIdentifier("csvLoadingState")
        case .streaming:
          ProgressView("Loaded \(viewModel.availableRowCount) rows…")
            .accessibilityIdentifier("csvLoadingState")
        case .loaded:
          VStack(spacing: 8) {
            Text("\(viewModel.availableRowCount) rows")
              .font(.headline)
            Text("Ready to display")
              .foregroundStyle(.secondary)
          }
        case .empty:
          EmptyCSVView()
        case let .failure(message):
          CSVErrorView(message: message)
        }
      }
      .navigationTitle("CSV Viewer")
      .navigationBarTitleDisplayMode(.inline)
      .safeAreaInset(edge: .top) {
        if !viewModel.displayedFilename.isEmpty {
          Text(viewModel.displayedFilename)
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)
            .padding(.vertical, 6)
            .background(.bar)
        }
      }
      .toolbar {
        ToolbarItem(placement: .primaryAction) {
          Button("Import", systemImage: "square.and.arrow.down") {
            isImporterPresented = true
          }
          .accessibilityIdentifier("importCSVButton")
        }
      }
      .fileImporter(
        isPresented: $isImporterPresented,
        allowedContentTypes: [.commaSeparatedText, .plainText],
        allowsMultipleSelection: false
      ) { result in
        switch result {
        case let .success(urls):
          if let url = urls.first {
            viewModel.importFile(at: url)
          }
        case let .failure(error):
          viewModel.handleImportFailure(error)
        }
      }
      .task {
        viewModel.loadBundledSampleIfNeeded()
      }
    }
  }
}
