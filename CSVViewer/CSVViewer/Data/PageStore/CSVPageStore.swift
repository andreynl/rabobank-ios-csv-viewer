protocol CSVPageStore: CSVPageProviding {
  func append(_ rows: [[String]]) async throws -> CSVRowPage
  func finish() async throws
}
