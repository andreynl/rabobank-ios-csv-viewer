enum CSVRowBufferError: Error, Equatable, Sendable {
  case rowExceedsPageLimit(maximumBytes: Int, actualBytes: Int)
}
