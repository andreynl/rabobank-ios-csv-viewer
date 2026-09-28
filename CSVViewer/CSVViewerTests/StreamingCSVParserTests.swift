import Foundation
import Testing
@testable import CSVViewer

struct StreamingCSVParserTests {
  @Test func parsesProvidedSampleAcrossChunks() throws {
    let csv = """
    "First name","Sur name","Issue count","Date of birth"
    "Theo","Jansen",5,"1978-01-02T00:00:00"
    "Fiona","de Vries",7,"1950-11-12T00:00:00"
    """

    let result = try parse(chunks: split(Data(csv.utf8), at: [17, 63, 101]))

    #expect(result.headers == ["First name", "Sur name", "Issue count", "Date of birth"])
    #expect(result.rows == [
      ["Theo", "Jansen", "5", "1978-01-02T00:00:00"],
      ["Fiona", "de Vries", "7", "1950-11-12T00:00:00"],
    ])
  }

  @Test func parsesQuotedSyntaxAndRowNormalization() throws {
    let csv = "first,middle,last,note\r\nTheo,,,\"hello, \"\"world\"\"\r\nline two\"\r\nFiona,de Vries"

    let result = try parse(chunks: [Data(csv.utf8)])

    #expect(result.headers == ["first", "middle", "last", "note"])
    #expect(result.rows == [
      ["Theo", "", "", "hello, \"world\"\nline two"],
      ["Fiona", "de Vries", "", ""],
    ])
  }

  @Test func preservesFinalRecordWithoutNewlineAndHeaderOnlyInput() throws {
    let document = try parse(chunks: [Data("name,count\nTheo,5".utf8)])
    let headerOnly = try parse(chunks: [Data("name,count".utf8)])

    #expect(document.headers == ["name", "count"])
    #expect(document.rows == [["Theo", "5"]])
    #expect(headerOnly.headers == ["name", "count"])
    #expect(headerOnly.rows.isEmpty)
  }

  @Test func handlesEscapedQuoteSplitAcrossChunks() throws {
    let prefix = Data("name,note\nTheo,\"hello \"".utf8)
    let suffix = Data("\"world\"\"\"".utf8)

    let result = try parse(chunks: [prefix, suffix])

    #expect(result.rows == [["Theo", "hello \"world\""]])
  }

  @Test func handlesCRLFSplitAcrossChunks() throws {
    let result = try parse(chunks: [
      Data("name,count\r".utf8),
      Data("\nTheo,5\r".utf8),
      Data("\n".utf8),
    ])

    #expect(result.headers == ["name", "count"])
    #expect(result.rows == [["Theo", "5"]])
  }

  @Test func handlesUTF8ScalarSplitAcrossChunks() throws {
    let prefix = Data("name,note\nTheo,".utf8)
    let euro = Array("€".utf8)

    let result = try parse(chunks: [
      prefix + Data(euro.prefix(1)),
      Data(euro.dropFirst().prefix(1)),
      Data(euro.dropFirst(2)),
    ])

    #expect(result.rows == [["Theo", "€"]])
  }

  @Test func removesBOMSplitAcrossChunks() throws {
    let result = try parse(chunks: [
      Data([0xEF]),
      Data([0xBB]),
      Data([0xBF]) + Data("name,count\nTheo,5".utf8),
    ])

    #expect(result.headers == ["name", "count"])
    #expect(result.rows == [["Theo", "5"]])
  }

  @Test func rejectsInvalidUTF8() {
    expectError(.invalidUTF8, chunks: [Data("name\n".utf8), Data([0xFF])])
  }

  @Test func rejectsUnterminatedQuotedField() {
    expectError(
      .unterminatedQuotedField,
      chunks: [Data("name,note\nTheo,\"unfinished".utf8)]
    )
  }

  @Test func rejectsQuoteInsideUnquotedField() {
    expectParserError(chunks: [Data("name\nTh\"eo".utf8)])
  }

  @Test func rejectsCharactersAfterClosingQuote() {
    expectParserError(chunks: [Data("name\n\"Theo\"junk".utf8)])
  }

  @Test func rejectsCharactersAfterClosingQuoteAcrossChunks() {
    expectParserError(chunks: [
      Data("name\n\"Theo\"".utf8),
      Data("junk".utf8),
    ])
  }

  @Test func acceptsEscapedQuoteAcrossChunks() throws {
    let result = try parse(chunks: [
      Data("name\n\"a\"".utf8),
      Data("\"b\"".utf8),
    ])

    #expect(result.rows == [["a\"b"]])
  }

  @Test func lateWideRowUsesGlobalRowNumber() {
    expectError(
      .rowHasTooManyFields(row: 2, expected: 2, actual: 3),
      chunks: [
        Data("name,count\nTheo,5\n".utf8),
        Data("Fiona,7,unexpected".utf8),
      ]
    )
  }

  private func parse(chunks: [Data]) throws -> (headers: [String], rows: [[String]]) {
    var parser = StreamingCSVParser()
    var headers: [String] = []
    var rows: [[String]] = []

    for chunk in chunks {
      let result = try parser.consume(chunk)
      if let emittedHeaders = result.headers {
        headers = emittedHeaders
      }
      rows.append(contentsOf: result.rows)
    }

    let finalResult = try parser.finish()
    if let emittedHeaders = finalResult.headers {
      headers = emittedHeaders
    }
    rows.append(contentsOf: finalResult.rows)
    return (headers, rows)
  }

  private func expectError(_ expected: CSVParserError, chunks: [Data]) {
    do {
      _ = try parse(chunks: chunks)
      Issue.record("Expected \(expected) to be thrown")
    } catch {
      #expect(error as? CSVParserError == expected)
    }
  }

  private func expectParserError(chunks: [Data]) {
    do {
      _ = try parse(chunks: chunks)
      Issue.record("Expected malformed quoted field to throw")
    } catch {
      #expect(error is CSVParserError)
    }
  }

  private func split(_ data: Data, at offsets: [Int]) -> [Data] {
    var lowerBound = data.startIndex
    var chunks: [Data] = []

    for offset in offsets {
      let upperBound = data.index(data.startIndex, offsetBy: min(offset, data.count))
      chunks.append(data[lowerBound..<upperBound])
      lowerBound = upperBound
    }
    chunks.append(data[lowerBound..<data.endIndex])
    return chunks
  }
}
