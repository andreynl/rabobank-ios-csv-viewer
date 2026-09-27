import Foundation

struct CSVParser: CSVParsing, Sendable {
  func parse(data: Data) throws -> CSVDocument {
    guard var contents = String(data: data, encoding: .utf8) else {
      throw CSVParserError.invalidUTF8
    }

    if contents.first == "\u{FEFF}" {
      contents.removeFirst()
    }
    guard !contents.isEmpty else {
      return CSVDocument(headers: [], rows: [])
    }

    let characters = Array(contents)
    var records: [[String]] = []
    var record: [String] = []
    var field = ""
    var isInsideQuotes = false
    var index = 0
    var endedWithRecordSeparator = false

    while index < characters.count {
      let character = characters[index]

      if isInsideQuotes {
        switch character {
        case "\"":
          if index + 1 < characters.count, characters[index + 1] == "\"" {
            field.append("\"")
            index += 1
          } else {
            isInsideQuotes = false
          }
        case "\r\n":
          field.append("\n")
        case "\r":
          if index + 1 < characters.count, characters[index + 1] == "\n" {
            index += 1
          }
          field.append("\n")
        default:
          field.append(character)
        }
        endedWithRecordSeparator = false
      } else {
        switch character {
        case "\"" where field.isEmpty:
          isInsideQuotes = true
          endedWithRecordSeparator = false
        case ",":
          record.append(field)
          field = ""
          endedWithRecordSeparator = false
        case "\r\n":
          record.append(field)
          records.append(record)
          record = []
          field = ""
          endedWithRecordSeparator = true
        case "\r", "\n":
          if character == "\r", index + 1 < characters.count, characters[index + 1] == "\n" {
            index += 1
          }
          record.append(field)
          records.append(record)
          record = []
          field = ""
          endedWithRecordSeparator = true
        default:
          field.append(character)
          endedWithRecordSeparator = false
        }
      }
      index += 1
    }

    guard !isInsideQuotes else {
      throw CSVParserError.unterminatedQuotedField
    }
    if !endedWithRecordSeparator {
      record.append(field)
      records.append(record)
    }

    guard let headers = records.first else {
      return CSVDocument(headers: [], rows: [])
    }

    let rows = try records.dropFirst().enumerated().map { offset, sourceRow in
      guard sourceRow.count <= headers.count else {
        throw CSVParserError.rowHasTooManyFields(
          row: offset + 1,
          expected: headers.count,
          actual: sourceRow.count
        )
      }
      return sourceRow + Array(repeating: "", count: headers.count - sourceRow.count)
    }

    return CSVDocument(headers: headers, rows: rows)
  }
}
