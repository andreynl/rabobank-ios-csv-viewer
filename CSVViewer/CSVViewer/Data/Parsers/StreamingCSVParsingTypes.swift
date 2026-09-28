struct CSVParserChunkResult: Equatable, Sendable {
  let headers: [String]?
  let rows: [[String]]
}

enum CSVParserError: Error, Equatable, Sendable {
  case invalidUTF8
  case unterminatedQuotedField
  case invalidQuote(row: Int)
  case unexpectedCharacterAfterClosingQuote(row: Int)
  case rowHasTooManyFields(row: Int, expected: Int, actual: Int)
}
