protocol CSVPageProviding: Sendable {
  var pageSize: Int { get }
  func pageIndex(containing rowIndex: Int) async throws -> Int
  func page(containing rowIndex: Int) async throws -> CSVRowPage
  func close() async
}

extension CSVPageProviding {
  func pageIndex(containing rowIndex: Int) async throws -> Int {
    rowIndex / pageSize
  }
}
