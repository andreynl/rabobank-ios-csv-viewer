struct CSVRowPage: Equatable, Sendable {
  let index: Int
  let startRow: Int
  let rows: [[String]]
}
