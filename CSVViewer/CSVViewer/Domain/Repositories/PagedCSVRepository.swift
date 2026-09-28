protocol PagedCSVRepository: Sendable {
  func loadSession(from source: CSVSource) async throws -> CSVLoadSession
}
