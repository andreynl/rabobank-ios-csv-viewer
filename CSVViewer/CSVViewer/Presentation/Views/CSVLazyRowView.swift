import SwiftUI

struct CSVLazyRowView: View {
  let values: [String]?
  let columnCount: Int
  let widths: [CGFloat]
  let isHeader: Bool
  private let formatter = CSVCellFormatter()

  var body: some View {
    HStack(spacing: 0) {
      ForEach(0..<columnCount, id: \.self) { column in
        Text(text(at: column))
          .font(isHeader ? .headline : .body)
          .lineLimit(1)
          .padding(.horizontal, 10)
          .frame(width: widths[column], height: 44, alignment: .leading)
          .background(isHeader ? Color(uiColor: .secondarySystemBackground) : .clear)
          .overlay { Rectangle().stroke(Color(uiColor: .separator), lineWidth: 0.5) }
          .redacted(reason: values == nil ? .placeholder : [])
      }
    }
  }

  private func text(at column: Int) -> String {
    guard let values else { return "Loading" }
    let value = values.indices.contains(column) ? values[column] : ""
    return formatter.string(from: value)
  }
}
