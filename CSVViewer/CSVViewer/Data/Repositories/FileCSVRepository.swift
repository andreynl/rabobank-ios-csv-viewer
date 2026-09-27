import Foundation

struct FileCSVRepository: CSVRepository, Sendable {
  private let parser: any CSVParsing
  private let bundle: Bundle
  private let urlAccess: any SecurityScopedURLAccessing

  init(
    parser: any CSVParsing,
    bundle: Bundle = .main,
    urlAccess: any SecurityScopedURLAccessing = SecurityScopedURLAccess()
  ) {
    self.parser = parser
    self.bundle = bundle
    self.urlAccess = urlAccess
  }

  func load(from source: CSVSource) async throws -> CSVDocument {
    switch source {
    case let .bundled(name, fileExtension):
      guard let url = bundle.url(forResource: name, withExtension: fileExtension) else {
        throw CSVLoadingError.resourceNotFound
      }
      return try await readAndParse(url)

    case let .file(url):
      return try await urlAccess.withAccess(to: url) { scopedURL in
        try await readAndParse(scopedURL)
      }
    }
  }

  private func readAndParse(_ url: URL) async throws -> CSVDocument {
    do {
      return try await Task.detached(priority: .userInitiated) { [parser] in
        let data = try Data(contentsOf: url)
        return try parser.parse(data: data)
      }.value
    } catch CSVParserError.invalidUTF8 {
      throw CSVLoadingError.invalidEncoding
    } catch is CSVParserError {
      throw CSVLoadingError.malformedCSV
    } catch let error as CSVLoadingError {
      throw error
    } catch {
      throw CSVLoadingError.readFailed
    }
  }
}
