protocol CSVPageProviding: Sendable {
  var pageSize: Int { get }
  func page(containing rowIndex: Int) async throws -> CSVRowPage
  func close() async
}
