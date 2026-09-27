enum CSVViewState: Equatable {
  case idle
  case loading
  case loaded(CSVDocument)
  case empty
  case failure(String)
}
