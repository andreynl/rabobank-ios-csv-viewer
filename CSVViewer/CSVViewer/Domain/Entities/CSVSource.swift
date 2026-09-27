import Foundation

enum CSVSource: Equatable, Sendable {
  case bundled(name: String, extension: String)
  case file(URL)
}
