import Foundation

protocol SecurityScopedURLAccessing: Sendable {
  func withAccess<T: Sendable>(
    to url: URL,
    operation: @Sendable (URL) async throws -> T
  ) async throws -> T
}

protocol URLResourceAccessing: Sendable {
  func startAccessing(_ url: URL) -> Bool
  func stopAccessing(_ url: URL)
}

struct FoundationURLResourceAccessor: URLResourceAccessing, Sendable {
  func startAccessing(_ url: URL) -> Bool {
    url.startAccessingSecurityScopedResource()
  }

  func stopAccessing(_ url: URL) {
    url.stopAccessingSecurityScopedResource()
  }
}

struct SecurityScopedURLAccess: SecurityScopedURLAccessing, Sendable {
  private let resourceAccessor: any URLResourceAccessing

  init(resourceAccessor: any URLResourceAccessing = FoundationURLResourceAccessor()) {
    self.resourceAccessor = resourceAccessor
  }

  func withAccess<T: Sendable>(
    to url: URL,
    operation: @Sendable (URL) async throws -> T
  ) async throws -> T {
    guard resourceAccessor.startAccessing(url) else {
      throw CSVLoadingError.accessDenied
    }
    defer { resourceAccessor.stopAccessing(url) }
    return try await operation(url)
  }
}
