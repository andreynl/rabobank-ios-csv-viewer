import Testing
@testable import CSVViewer

struct CSVRowBufferTests {
  @Test func returnsOrderedFullAndFinalBatches() {
    var buffer = CSVRowBuffer(pageSize: 2)
    buffer.append(contentsOf: [["0"], ["1"], ["2"], ["3"], ["4"]])

    #expect(buffer.nextFullPage() == [["0"], ["1"]])
    #expect(buffer.nextFullPage() == [["2"], ["3"]])
    #expect(buffer.nextFullPage() == nil)
    #expect(buffer.takeRemaining() == [["4"]])
  }

  @Test func returnsNilUntilAFullPageExists() {
    var buffer = CSVRowBuffer(pageSize: 2)
    buffer.append(contentsOf: [["0"]])

    #expect(buffer.nextFullPage() == nil)

    buffer.append(contentsOf: [["1"]])
    #expect(buffer.nextFullPage() == [["0"], ["1"]])
  }

  @Test func doesNotReturnRowsTwice() {
    var buffer = CSVRowBuffer(pageSize: 2)
    buffer.append(contentsOf: [["0"], ["1"]])

    #expect(buffer.nextFullPage() == [["0"], ["1"]])
    #expect(buffer.nextFullPage() == nil)
    #expect(buffer.takeRemaining().isEmpty)
    #expect(buffer.takeRemaining().isEmpty)
  }
}
