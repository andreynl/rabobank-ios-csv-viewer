protocol CSVRepository: Sendable {
  func load(from source: CSVSource) async throws -> CSVDocument
}
