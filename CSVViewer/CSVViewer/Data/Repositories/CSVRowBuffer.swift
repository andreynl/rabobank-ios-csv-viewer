struct CSVRowBuffer {
  private let pageSize: Int
  private let maximumPageBytes: Int
  private var rows: [[String]] = []
  private var bufferedBytes = 0

  init(
    pageSize: Int,
    maximumPageBytes: Int = CSVResourceLimits.default.maximumPageBytes
  ) {
    precondition(pageSize > 0)
    precondition(maximumPageBytes > 0)
    self.pageSize = pageSize
    self.maximumPageBytes = maximumPageBytes
  }

  mutating func append(_ row: [String]) throws -> [[String]]? {
    let rowBytes = estimatedBytes(for: row)
    guard rowBytes <= maximumPageBytes else {
      throw CSVRowBufferError.rowExceedsPageLimit(
        maximumBytes: maximumPageBytes,
        actualBytes: rowBytes
      )
    }

    if !rows.isEmpty, bufferedBytes > maximumPageBytes - rowBytes {
      let page = takeBufferedRows()
      rows.append(row)
      bufferedBytes = rowBytes
      return page
    }

    rows.append(row)
    bufferedBytes += rowBytes
    return rows.count == pageSize ? takeBufferedRows() : nil
  }

  mutating func takeRemaining() -> [[String]] {
    takeBufferedRows()
  }

  private mutating func takeBufferedRows() -> [[String]] {
    let page = rows
    rows.removeAll(keepingCapacity: true)
    bufferedBytes = 0
    return page
  }

  private func estimatedBytes(for row: [String]) -> Int {
    var byteCount = max(row.count - 1, 0)
    for field in row {
      let (sum, overflow) = byteCount.addingReportingOverflow(field.utf8.count)
      if overflow { return .max }
      byteCount = sum
    }
    return byteCount
  }
}
