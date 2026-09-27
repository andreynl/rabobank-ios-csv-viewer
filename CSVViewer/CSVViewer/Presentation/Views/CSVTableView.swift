import SwiftUI

struct CSVTableView: View {
  let document: CSVDocument

  var body: some View {
    ScrollView([.horizontal, .vertical], showsIndicators: true) {
      Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
        row(document.headers, isHeader: true)
        ForEach(Array(document.rows.enumerated()), id: \.offset) { _, values in
          row(values, isHeader: false)
        }
      }
      .padding(16)
    }
    .scrollBounceBehavior(.basedOnSize, axes: [.horizontal, .vertical])
    .accessibilityIdentifier("csvTable")
  }

  @ViewBuilder
  private func row(_ values: [String], isHeader: Bool) -> some View {
    GridRow {
      ForEach(Array(values.enumerated()), id: \.offset) { _, value in
        Text(value)
          .font(isHeader ? .headline : .body)
          .lineLimit(1)
          .fixedSize(horizontal: true, vertical: false)
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
          .padding(.horizontal, 10)
          .padding(.vertical, 8)
          .background(isHeader ? Color(uiColor: .secondarySystemBackground) : .clear)
          .overlay {
            Rectangle()
              .stroke(Color(uiColor: .separator), lineWidth: 0.5)
          }
      }
    }
  }
}
