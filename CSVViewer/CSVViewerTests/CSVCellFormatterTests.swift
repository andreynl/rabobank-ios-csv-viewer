import Foundation
import Testing
@testable import CSVViewer

struct CSVCellFormatterTests {
  @Test func formatsISODateUsingRequestedLocale() {
    let formatter = CSVCellFormatter(locale: Locale(identifier: "nl_NL"))

    let result = formatter.string(from: "1978-01-02T00:00:00")

    #expect(result == "02-01-1978")
  }

  @Test func leavesValueWithDatePrefixUnchanged() {
    let formatter = CSVCellFormatter(locale: Locale(identifier: "nl_NL"))
    let value = "1978-01-02T00:00:00-not-a-date"

    #expect(formatter.string(from: value) == value)
  }
}
