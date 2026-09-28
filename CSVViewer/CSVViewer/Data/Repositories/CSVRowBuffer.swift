struct CSVRowBuffer {
  private let pageSize: Int
  private var rows: [[String]] = []
  private var consumedCount = 0

  init(pageSize: Int) {
    precondition(pageSize > 0)
    self.pageSize = pageSize
  }

  mutating func append(contentsOf newRows: [[String]]) {
    compactConsumedRows()
    rows.append(contentsOf: newRows)
  }

  mutating func nextFullPage() -> [[String]]? {
    guard rows.count - consumedCount >= pageSize else { return nil }
    let endIndex = consumedCount + pageSize
    let page = Array(rows[consumedCount..<endIndex])
    consumedCount = endIndex

    if consumedCount == rows.count {
      rows.removeAll(keepingCapacity: true)
      consumedCount = 0
    }
    return page
  }

  mutating func takeRemaining() -> [[String]] {
    let remaining = Array(rows.dropFirst(consumedCount))
    rows.removeAll(keepingCapacity: false)
    consumedCount = 0
    return remaining
  }

  private mutating func compactConsumedRows() {
    guard consumedCount > 0 else { return }
    rows.removeFirst(consumedCount)
    consumedCount = 0
  }
}
