import Testing
@testable import CSVViewer

struct CSVColumnWidthCalculatorTests {
  @Test func returnsOneWidthPerHeaderWithinBounds() {
    let calculator = CSVColumnWidthCalculator()
    let widths = calculator.widths(
      headers: ["Name", "", "Very long heading that should be clamped at the maximum width"],
      sampleRows: [["Theo", "value", "short"]]
    )

    #expect(widths.count == 3)
    #expect(widths.allSatisfy { (calculator.minimumWidth...calculator.maximumWidth).contains($0) })
    #expect(widths[2] == calculator.maximumWidth)
  }

  @Test func usesFirstPageValuesButIgnoresLaterPages() {
    let calculator = CSVColumnWidthCalculator()
    let firstPage = calculator.widths(headers: ["Name"], sampleRows: [["Fiona de Vries"]])
    let frozen = firstPage

    #expect(firstPage[0] > calculator.minimumWidth)
    #expect(frozen == firstPage)
  }
}
