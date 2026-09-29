import Foundation

actor FileBackedCSVPageStore: CSVPageStore {
  private struct PageLocation {
    let index: Int
    let startRow: Int
    let rowCount: Int

    func contains(_ rowIndex: Int) -> Bool {
      rowIndex >= startRow && rowIndex < startRow + rowCount
    }
  }

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
  let maximumPageBytes: Int

  private let fileManager: FileManager
  private var cache: [Int: CSVRowPage] = [:]
  private var recency: [Int] = []
  private var pageLocations: [PageLocation] = []
  private var nextPageIndex = 0
  private var totalRowCount = 0
  private var isClosed = false

  init(
    directoryURL: URL,
    pageSize: Int = CSVPageConfiguration.defaultPageSize,
    cacheCapacity: Int = 5,
    maximumPageBytes: Int = CSVResourceLimits.default.maximumPageBytes,
    fileManager: FileManager = .default
  ) throws {
    guard pageSize > 0, cacheCapacity >= 0, maximumPageBytes > 0 else {
      throw CSVPageStoreError.invalidConfiguration
    }
    self.directoryURL = directoryURL
    self.pageSize = pageSize
    self.cacheCapacity = cacheCapacity
    self.maximumPageBytes = maximumPageBytes
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
    let page = CSVRowPage(
      index: nextPageIndex,
      startRow: totalRowCount,
      rows: rows
    )
    let destinationURL = pageURL(for: page.index)
    do {
      let encoder = PropertyListEncoder()
      encoder.outputFormat = .binary
      let data = try encoder.encode(StoredPage(page))
      guard data.count <= maximumPageBytes else {
        throw CSVPageStoreError.encodedPageTooLarge(
          maximumBytes: maximumPageBytes,
          actualBytes: data.count
        )
      }
      try Task.checkCancellation()
      try data.write(to: destinationURL, options: .atomic)
      try Task.checkCancellation()
    } catch is CancellationError {
      try? fileManager.removeItem(at: destinationURL)
      throw CancellationError()
    } catch let error as CSVPageStoreError {
      try? fileManager.removeItem(at: destinationURL)
      throw error
    } catch {
      try? fileManager.removeItem(at: destinationURL)
      throw CSVPageStoreError.persistenceFailed
    }

    nextPageIndex += 1
    totalRowCount += rows.count
    pageLocations.append(PageLocation(
      index: page.index,
      startRow: page.startRow,
      rowCount: page.rows.count
    ))
    cachePage(page)
    return page
  }

  func finish() async throws {
    try Task.checkCancellation()
  }

  func pageIndex(containing rowIndex: Int) async throws -> Int {
    try location(containing: rowIndex).index
  }

  func page(containing rowIndex: Int) async throws -> CSVRowPage {
    let location = try location(containing: rowIndex)
    let pageIndex = location.index
    if let cached = cache[pageIndex] {
      touch(pageIndex)
      guard location.contains(rowIndex),
            cached.rows.indices.contains(rowIndex - cached.startRow) else {
        throw CSVPageStoreError.pageNotFound(rowIndex)
      }
      return cached
    }

    let url = pageURL(for: pageIndex)
    guard fileManager.fileExists(atPath: url.path) else {
      throw CSVPageStoreError.pageNotFound(rowIndex)
    }

    let storedPage: StoredPage
    do {
      let data = try Data(contentsOf: url)
      storedPage = try PropertyListDecoder().decode(StoredPage.self, from: data)
    } catch {
      throw CSVPageStoreError.persistenceFailed
    }
    let page = storedPage.page
    guard page.index == pageIndex,
          page.startRow == location.startRow,
          page.rows.count == location.rowCount,
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

  private func location(containing rowIndex: Int) throws -> PageLocation {
    guard rowIndex >= 0 else {
      throw CSVPageStoreError.pageNotFound(rowIndex)
    }
    var lowerBound = 0
    var upperBound = pageLocations.count
    while lowerBound < upperBound {
      let middle = lowerBound + (upperBound - lowerBound) / 2
      let location = pageLocations[middle]
      if rowIndex < location.startRow {
        upperBound = middle
      } else if rowIndex >= location.startRow + location.rowCount {
        lowerBound = middle + 1
      } else {
        return location
      }
    }
    throw CSVPageStoreError.pageNotFound(rowIndex)
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
