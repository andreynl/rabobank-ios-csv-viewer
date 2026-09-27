enum CSVLoadingError: Error, Equatable, Sendable {
  case resourceNotFound
  case accessDenied
  case readFailed
  case invalidEncoding
  case malformedCSV
}
