import SwiftUI

struct CSVTableView: View {
  let viewModel: CSVViewModel
  @State private var widths: [CGFloat] = []
  private let widthCalculator = CSVColumnWidthCalculator()

  var body: some View {
    VStack(spacing: 0) {
      status
      pageLoadErrorBanner
      ScrollView(.horizontal, showsIndicators: true) {
        VStack(alignment: .leading, spacing: 0) {
          CSVLazyRowView(
            values: viewModel.headers,
            columnCount: viewModel.headers.count,
            widths: resolvedWidths,
            isHeader: true
          )

          ScrollView(.vertical, showsIndicators: true) {
            LazyVStack(alignment: .leading, spacing: 0) {
              ForEach(0..<viewModel.availableRowCount, id: \.self) { rowIndex in
                CSVLazyRowView(
                  values: viewModel.row(at: rowIndex),
                  columnCount: viewModel.headers.count,
                  widths: resolvedWidths,
                  isHeader: false
                )
                .id(rowIndex)
                .accessibilityIdentifier("csvRow-\(rowIndex)")
                .task(id: rowIndex) {
                  await viewModel.loadPage(containing: rowIndex)
                  await prefetch(after: rowIndex)
                  freezeWidthsIfPossible()
                }
              }
            }
          }
        }
        .padding(16)
      }
      .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
    }
    .accessibilityIdentifier("csvTable")
    .task(id: viewModel.headers) { freezeWidthsIfPossible() }
  }

  @ViewBuilder
  private var pageLoadErrorBanner: some View {
    if let message = viewModel.pageLoadErrorMessage {
      HStack(spacing: 12) {
        Image(systemName: "exclamationmark.triangle.fill")
          .foregroundStyle(.red)
        Text(message)
          .font(.caption)
          .frame(maxWidth: .infinity, alignment: .leading)
        Button("Retry") {
          Task { await viewModel.retryFailedPages() }
        }
        .buttonStyle(.bordered)
        .accessibilityIdentifier("retryPageLoadButton")
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 8)
      .background(Color.red.opacity(0.08))
      .accessibilityElement(children: .contain)
      .accessibilityAddTraits(.updatesFrequently)
      .accessibilityIdentifier("pageLoadErrorBanner")
    }
  }

  private var resolvedWidths: [CGFloat] {
    if widths.count == viewModel.headers.count { return widths }
    return widthCalculator.widths(headers: viewModel.headers, sampleRows: [])
  }

  @ViewBuilder
  private var status: some View {
    Text(viewModel.isComplete
      ? "\(viewModel.availableRowCount) rows"
      : "Loaded \(viewModel.availableRowCount) rows…")
      .font(.caption)
      .foregroundStyle(.secondary)
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, 16)
      .padding(.vertical, 6)
  }

  private func prefetch(after rowIndex: Int) async {
    let prefetchDistance = max(viewModel.pageSize / 10, 1)
    let offset = rowIndex % viewModel.pageSize
    guard offset >= viewModel.pageSize - prefetchDistance else { return }
    await viewModel.loadPage(containing: min(
      rowIndex + prefetchDistance,
      viewModel.availableRowCount - 1
    ))
  }

  private func freezeWidthsIfPossible() {
    guard widths.isEmpty || widths.count != viewModel.headers.count else { return }
    guard viewModel.availableRowCount > 0 else { return }
    let samples = (0..<min(viewModel.availableRowCount, 500)).compactMap { viewModel.row(at: $0) }
    guard !samples.isEmpty else { return }
    widths = widthCalculator.widths(headers: viewModel.headers, sampleRows: samples)
  }
}
