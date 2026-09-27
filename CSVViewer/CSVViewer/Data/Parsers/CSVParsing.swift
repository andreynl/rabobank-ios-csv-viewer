import Foundation

protocol CSVParsing: Sendable {
  func parse(data: Data) throws -> CSVDocument
}

enum CSVParserError: Error, Equatable, Sendable {
  case invalidUTF8
  case unterminatedQuotedField
  case rowHasTooManyFields(row: Int, expected: Int, actual: Int)
}
