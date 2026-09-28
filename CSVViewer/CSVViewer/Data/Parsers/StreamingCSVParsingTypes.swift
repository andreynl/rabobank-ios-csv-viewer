struct CSVParserChunkResult: Equatable, Sendable {
  let headers: [String]?
  let rows: [[String]]
}

enum CSVParserError: Error, Equatable, Sendable {
  case invalidUTF8
  case unterminatedQuotedField
  case rowHasTooManyFields(row: Int, expected: Int, actual: Int)
}
