import Foundation

actor FileBackedCSVPageStore: CSVPageStore {
  private struct StoredPage: Codable {
    let index: Int
    let startRow: Int
    let rows: [[String]]

    init(_ page: CSVRowPage) {
      index = page.index
      startRow = page.startRow
      rows = page.rows
    }

    var page: CSVRowPage {
      CSVRowPage(index: index, startRow: startRow, rows: rows)
    }
  }

  let directoryURL: URL
  let pageSize: Int
  let cacheCapacity: Int

  private let fileManager: FileManager
  private var cache: [Int: CSVRowPage] = [:]
  private var recency: [Int] = []
  private var nextPageIndex = 0
  private var totalRowCount = 0
  private var hasPartialPage = false
  private var isClosed = false

  init(
    directoryURL: URL,
    pageSize: Int = 500,
    cacheCapacity: Int = 5,
    fileManager: FileManager = .default
  ) throws {
    self.directoryURL = directoryURL
    self.pageSize = pageSize
    self.cacheCapacity = cacheCapacity
    self.fileManager = fileManager
    try fileManager.createDirectory(
      at: directoryURL,
      withIntermediateDirectories: true
    )
  }

  var cachedPageIndexes: [Int] {
    recency
  }

  func append(_ rows: [[String]]) async throws -> CSVRowPage {
    try Task.checkCancellation()
    guard !rows.isEmpty else {
      throw CSVPageStoreError.emptyPage
    }
    guard rows.count <= pageSize else {
      throw CSVPageStoreError.pageTooLarge(maximum: pageSize, actual: rows.count)
    }
    guard !hasPartialPage else {
      throw CSVPageStoreError.appendAfterPartialPage
    }

    let page = CSVRowPage(
      index: nextPageIndex,
      startRow: totalRowCount,
      rows: rows
    )
    let encoder = PropertyListEncoder()
    encoder.outputFormat = .binary
    let data = try encoder.encode(StoredPage(page))
    try Task.checkCancellation()
    let destinationURL = pageURL(for: page.index)
    do {
      try data.write(to: destinationURL, options: .atomic)
      try Task.checkCancellation()
    } catch {
      try? fileManager.removeItem(at: destinationURL)
      throw error
    }

    nextPageIndex += 1
    totalRowCount += rows.count
    hasPartialPage = rows.count < pageSize
    cachePage(page)
    return page
  }

  func finish() async throws {
    try Task.checkCancellation()
  }

  func page(containing rowIndex: Int) async throws -> CSVRowPage {
    guard rowIndex >= 0 else {
      throw CSVPageStoreError.pageNotFound(rowIndex)
    }

    let pageIndex = rowIndex / pageSize
    if let cached = cache[pageIndex] {
      touch(pageIndex)
      guard cached.rows.indices.contains(rowIndex - cached.startRow) else {
        throw CSVPageStoreError.pageNotFound(rowIndex)
      }
      return cached
    }

    let url = pageURL(for: pageIndex)
    guard fileManager.fileExists(atPath: url.path) else {
      throw CSVPageStoreError.pageNotFound(rowIndex)
    }

    let data = try Data(contentsOf: url)
    let storedPage = try PropertyListDecoder().decode(StoredPage.self, from: data)
    let page = storedPage.page
    guard page.index == pageIndex,
          page.rows.indices.contains(rowIndex - page.startRow) else {
      throw CSVPageStoreError.invalidPage(pageIndex)
    }
    cachePage(page)
    return page
  }

  func close() async {
    guard !isClosed else { return }
    isClosed = true
    cache.removeAll(keepingCapacity: false)
    recency.removeAll(keepingCapacity: false)
    try? fileManager.removeItem(at: directoryURL)
  }

  private func pageURL(for index: Int) -> URL {
    directoryURL.appendingPathComponent(
      String(format: "page-%08d.plist", index),
      isDirectory: false
    )
  }

  private func cachePage(_ page: CSVRowPage) {
    cache[page.index] = page
    touch(page.index)

    while recency.count > cacheCapacity, let leastRecent = recency.first {
      recency.removeFirst()
      cache.removeValue(forKey: leastRecent)
    }
  }

  private func touch(_ pageIndex: Int) {
    recency.removeAll { $0 == pageIndex }
    recency.append(pageIndex)
  }
}
