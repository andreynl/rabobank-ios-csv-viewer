import Testing
@testable import CSVViewer

struct CSVRowBufferTests {
  @Test func emitsPageAtRowCountLimit() throws {
    var buffer = CSVRowBuffer(pageSize: 2, maximumPageBytes: 100)

    #expect(try buffer.append(["0"]) == nil)
    #expect(try buffer.append(["1"]) == [["0"], ["1"]])
    #expect(buffer.takeRemaining().isEmpty)
  }

  @Test func emitsCurrentPageBeforeByteLimitWouldBeExceeded() throws {
    var buffer = CSVRowBuffer(pageSize: 3, maximumPageBytes: 5)

    #expect(try buffer.append(["aa"]) == nil)
    #expect(try buffer.append(["bb"]) == nil)
    #expect(try buffer.append(["cc"]) == [["aa"], ["bb"]])
    #expect(buffer.takeRemaining() == [["cc"]])
  }

  @Test func retainsBoundaryRowForNextOrderedPage() throws {
    var buffer = CSVRowBuffer(pageSize: 3, maximumPageBytes: 5)
    var emitted: [[[String]]] = []

    for value in ["00", "11", "22", "33", "44"] {
      if let page = try buffer.append([value]) {
        emitted.append(page)
      }
    }
    emitted.append(buffer.takeRemaining())

    #expect(emitted == [
      [["00"], ["11"]],
      [["22"], ["33"]],
      [["44"]],
    ])
  }

  @Test func rejectsSingleRowLargerThanPageBudget() {
    var buffer = CSVRowBuffer(pageSize: 3, maximumPageBytes: 5)

    #expect(throws: CSVRowBufferError.rowExceedsPageLimit(maximumBytes: 5, actualBytes: 6)) {
      try buffer.append(["abcdef"])
    }
    #expect(buffer.takeRemaining().isEmpty)
  }

  @Test func estimatesRowsUsingUTF8BytesAndCommaSeparators() throws {
    var buffer = CSVRowBuffer(pageSize: 3, maximumPageBytes: 4)

    #expect(try buffer.append(["€"]) == nil)
    #expect(try buffer.append(["a", "b"]) == [["€"]])
    #expect(buffer.takeRemaining() == [["a", "b"]])
  }

  @Test func takeRemainingResetsRowsAndByteAccounting() throws {
    var buffer = CSVRowBuffer(pageSize: 2, maximumPageBytes: 4)
    #expect(try buffer.append(["abc"]) == nil)
    #expect(buffer.takeRemaining() == [["abc"]])

    #expect(try buffer.append(["def"]) == nil)
    #expect(buffer.takeRemaining() == [["def"]])
    #expect(buffer.takeRemaining().isEmpty)
  }
}
