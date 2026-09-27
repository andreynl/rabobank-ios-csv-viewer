import Foundation
import Testing
@testable import CSVViewer

struct CSVParserTests {
  private let parser = CSVParser()

  @Test func parsesProvidedSampleShape() throws {
    let csv = """
    "First name","Sur name","Issue count","Date of birth"
    "Theo","Jansen",5,"1978-01-02T00:00:00"
    "Fiona","de Vries",7,"1950-11-12T00:00:00"
    "Petra","Boersma",1,"2001-04-20T00:00:00"
    """

    let document = try parser.parse(data: Data(csv.utf8))

    #expect(document.headers == ["First name", "Sur name", "Issue count", "Date of birth"])
    #expect(document.rows.count == 3)
    #expect(document.rows[1] == ["Fiona", "de Vries", "7", "1950-11-12T00:00:00"])
  }

  @Test func retainsFinalRecordWithoutNewline() throws {
    let document = try parse("name,count\nTheo,5")
    #expect(document == CSVDocument(headers: ["name", "count"], rows: [["Theo", "5"]]))
  }

  @Test func parsesQuotedCommasAndEscapedQuotes() throws {
    let document = try parse("name,note\nTheo,\"hello, \"\"world\"\"\"")
    #expect(document.rows == [["Theo", "hello, \"world\""]])
  }

  @Test func parsesMultilineQuotedField() throws {
    let document = try parse("name,note\nTheo,\"line one\nline two\"")
    #expect(document.rows == [["Theo", "line one\nline two"]])
  }

  @Test func parsesCRLFAndNormalizesQuotedCRLF() throws {
    let document = try parse("name,note\r\nTheo,\"line one\r\nline two\"\r\n")
    #expect(document.rows == [["Theo", "line one\nline two"]])
  }

  @Test func removesUTF8ByteOrderMark() throws {
    let bytes = [0xEF, 0xBB, 0xBF] + Array("name,count\nTheo,5".utf8)
    let document = try parser.parse(data: Data(bytes))
    #expect(document.headers == ["name", "count"])
  }

  @Test func preservesEmptyAndTrailingFields() throws {
    let document = try parse("first,middle,last\nTheo,,\n,Fiona,Vries")
    #expect(document.rows == [["Theo", "", ""], ["", "Fiona", "Vries"]])
  }

  @Test func padsRowsShorterThanHeader() throws {
    let document = try parse("first,middle,last\nTheo")
    #expect(document.rows == [["Theo", "", ""]])
  }

  @Test func emptyInputReturnsEmptyDocument() throws {
    #expect(try parser.parse(data: Data()) == CSVDocument(headers: [], rows: []))
  }

  @Test func headerOnlyInputRetainsHeaders() throws {
    #expect(try parse("name,count") == CSVDocument(headers: ["name", "count"], rows: []))
  }

  @Test func rejectsInvalidUTF8() {
    expectError(.invalidUTF8) {
      _ = try parser.parse(data: Data([0xFF, 0xFE]))
    }
  }

  @Test func rejectsUnterminatedQuotedField() {
    expectError(.unterminatedQuotedField) {
      _ = try parse("name,note\nTheo,\"unfinished")
    }
  }

  @Test func rejectsRowsWiderThanHeader() {
    expectError(.rowHasTooManyFields(row: 1, expected: 2, actual: 3)) {
      _ = try parse("name,count\nTheo,5,unexpected")
    }
  }

  private func parse(_ string: String) throws -> CSVDocument {
    try parser.parse(data: Data(string.utf8))
  }

  private func expectError(_ expectedError: CSVParserError, operation: () throws -> Void) {
    do {
      try operation()
      Issue.record("Expected \(expectedError) to be thrown")
    } catch {
      #expect(error as? CSVParserError == expectedError)
    }
  }
}
