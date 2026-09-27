struct CSVDocument: Equatable, Sendable {
  let headers: [String]
  let rows: [[String]]
}
