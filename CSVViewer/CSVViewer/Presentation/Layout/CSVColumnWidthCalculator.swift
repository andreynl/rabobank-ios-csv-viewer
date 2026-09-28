import CoreGraphics

struct CSVColumnWidthCalculator: Sendable {
  let minimumWidth: CGFloat = 100
  let maximumWidth: CGFloat = 280
  private let characterWidth: CGFloat = 9
  private let horizontalPadding: CGFloat = 24

  func widths(headers: [String], sampleRows: [[String]]) -> [CGFloat] {
    headers.indices.map { column in
      let values = [headers[column]] + sampleRows.map { row in
        row.indices.contains(column) ? row[column] : ""
      }
      let longest = values.map(\.count).max() ?? 0
      return min(max(CGFloat(longest) * characterWidth + horizontalPadding, minimumWidth), maximumWidth)
    }
  }
}
