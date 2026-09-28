import SwiftUI

struct CSVTableView: View {
  let viewModel: CSVViewModel
  @State private var widths: [CGFloat] = []
  private let widthCalculator = CSVColumnWidthCalculator()

  var body: some View {
    VStack(spacing: 0) {
      status
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
    let offset = rowIndex % 500
    guard offset >= 450 else { return }
    await viewModel.loadPage(containing: min(rowIndex + 50, viewModel.availableRowCount - 1))
  }

  private func freezeWidthsIfPossible() {
    guard widths.isEmpty || widths.count != viewModel.headers.count else { return }
    let samples = (0..<min(viewModel.availableRowCount, 500)).compactMap { viewModel.row(at: $0) }
    guard viewModel.availableRowCount == 0 || !samples.isEmpty else { return }
    widths = widthCalculator.widths(headers: viewModel.headers, sampleRows: samples)
  }
}
