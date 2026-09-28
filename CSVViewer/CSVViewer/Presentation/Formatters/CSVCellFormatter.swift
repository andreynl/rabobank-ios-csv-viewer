import Foundation

struct CSVCellFormatter {
  private let inputFormatter: DateFormatter
  private let outputFormatter: DateFormatter

  init(locale: Locale = .autoupdatingCurrent) {
    let inputFormatter = DateFormatter()
    inputFormatter.calendar = Calendar(identifier: .gregorian)
    inputFormatter.locale = Locale(identifier: "en_US_POSIX")
    inputFormatter.timeZone = TimeZone(secondsFromGMT: 0)
    inputFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
    inputFormatter.isLenient = false
    self.inputFormatter = inputFormatter

    let outputFormatter = DateFormatter()
    outputFormatter.locale = locale
    outputFormatter.dateStyle = .short
    outputFormatter.timeStyle = .none
    self.outputFormatter = outputFormatter
  }

  func string(from value: String) -> String {
    guard let date = inputFormatter.date(from: value) else { return value }
    return outputFormatter.string(from: date)
  }
}
