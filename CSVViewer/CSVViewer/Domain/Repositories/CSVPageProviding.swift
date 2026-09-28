protocol CSVPageProviding: Sendable {
  func page(containing rowIndex: Int) async throws -> CSVRowPage
  func close() async
}
