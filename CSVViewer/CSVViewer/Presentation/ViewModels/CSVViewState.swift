enum CSVViewState: Equatable {
  case idle
  case loading
  case streaming
  case loaded
  case empty
  case failure(String)
}
