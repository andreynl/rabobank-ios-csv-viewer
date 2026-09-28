enum CSVPageStoreError: Error, Equatable, Sendable {
  case emptyPage
  case pageTooLarge(maximum: Int, actual: Int)
  case appendAfterPartialPage
  case pageNotFound(Int)
  case invalidPage(Int)
}
