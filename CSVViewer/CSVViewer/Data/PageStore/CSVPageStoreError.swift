enum CSVPageStoreError: Error, Equatable, Sendable {
  case invalidConfiguration
  case persistenceFailed
  case emptyPage
  case pageTooLarge(maximum: Int, actual: Int)
  case pageNotFound(Int)
  case invalidPage(Int)
  case encodedPageTooLarge(maximumBytes: Int, actualBytes: Int)
}
