struct CSVLoadProgress: Equatable, Sendable {
  let headers: [String]
  let availableRowCount: Int
  let fractionCompleted: Double?
  let isComplete: Bool
}
