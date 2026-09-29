import Foundation

struct StreamingCSVParser: Sendable {
  private enum FieldState: Equatable, Sendable {
    case unquoted
    case quoted
    case afterClosingQuote
  }

  private static let utf8BOM: [UInt8] = [0xEF, 0xBB, 0xBF]

  private let limits: CSVResourceLimits
  private var headers: [String]?
  private var record: [String] = []
  private var fieldBytes: [UInt8] = []
  private var bomCandidate: [UInt8] = []
  private var dataRowCount = 0
  private var rowByteCount = 0
  private var fieldState = FieldState.unquoted
  private var shouldSkipLineFeed = false
  private var hasResolvedBOM = false
  private var hasInputSinceRecordSeparator = false
  private var isFinished = false

  init(limits: CSVResourceLimits = .default) {
    self.limits = limits
  }

  mutating func consume(_ data: Data) throws -> CSVParserChunkResult {
    try validateConfiguration()
    guard !isFinished else {
      return CSVParserChunkResult(headers: nil, rows: [])
    }

    var emittedHeaders: [String]?
    var emittedRows: [[String]] = []

    for byte in data {
      if !hasResolvedBOM {
        try resolveBOM(with: byte, headers: &emittedHeaders, rows: &emittedRows)
      } else {
        try process(byte, headers: &emittedHeaders, rows: &emittedRows)
      }
    }

    return CSVParserChunkResult(headers: emittedHeaders, rows: emittedRows)
  }

  mutating func finish() throws -> CSVParserChunkResult {
    try validateConfiguration()
    guard !isFinished else {
      return CSVParserChunkResult(headers: nil, rows: [])
    }

    var emittedHeaders: [String]?
    var emittedRows: [[String]] = []

    if !hasResolvedBOM {
      hasResolvedBOM = true
      if bomCandidate != Self.utf8BOM {
        for byte in bomCandidate {
          try process(byte, headers: &emittedHeaders, rows: &emittedRows)
        }
      }
      bomCandidate.removeAll(keepingCapacity: false)
    }

    guard fieldState != .quoted else {
      throw CSVParserError.unterminatedQuotedField
    }
    fieldState = .unquoted

    if hasInputSinceRecordSeparator {
      try completeRecord(headers: &emittedHeaders, rows: &emittedRows)
    }

    isFinished = true
    return CSVParserChunkResult(headers: emittedHeaders, rows: emittedRows)
  }

  private mutating func resolveBOM(
    with byte: UInt8,
    headers emittedHeaders: inout [String]?,
    rows emittedRows: inout [[String]]
  ) throws {
    bomCandidate.append(byte)

    let expectedPrefix = Self.utf8BOM.prefix(bomCandidate.count)
    if bomCandidate.elementsEqual(expectedPrefix), bomCandidate.count < Self.utf8BOM.count {
      return
    }

    hasResolvedBOM = true
    if bomCandidate != Self.utf8BOM {
      for candidateByte in bomCandidate {
        try process(candidateByte, headers: &emittedHeaders, rows: &emittedRows)
      }
    }
    bomCandidate.removeAll(keepingCapacity: false)
  }

  private mutating func process(
    _ byte: UInt8,
    headers emittedHeaders: inout [String]?,
    rows emittedRows: inout [[String]]
  ) throws {
    if shouldSkipLineFeed {
      shouldSkipLineFeed = false
      if byte == Self.lineFeed {
        if fieldState == .quoted {
          try countRowByte()
        }
        return
      }
    }

    switch fieldState {
    case .quoted:
      try countRowByte()
      switch byte {
      case Self.quote:
        fieldState = .afterClosingQuote
      case Self.carriageReturn:
        try appendFieldByte(Self.lineFeed)
        shouldSkipLineFeed = true
      default:
        try appendFieldByte(byte)
      }
      hasInputSinceRecordSeparator = true
      return
    case .afterClosingQuote:
      switch byte {
      case Self.quote:
        try countRowByte()
        try appendFieldByte(Self.quote)
        fieldState = .quoted
        hasInputSinceRecordSeparator = true
      case Self.comma:
        try countRowByte()
        try completeField()
        fieldState = .unquoted
        hasInputSinceRecordSeparator = true
      case Self.carriageReturn:
        try completeRecord(headers: &emittedHeaders, rows: &emittedRows)
        fieldState = .unquoted
        shouldSkipLineFeed = true
        hasInputSinceRecordSeparator = false
      case Self.lineFeed:
        try completeRecord(headers: &emittedHeaders, rows: &emittedRows)
        fieldState = .unquoted
        hasInputSinceRecordSeparator = false
      default:
        try countRowByte()
        throw CSVParserError.unexpectedCharacterAfterClosingQuote(row: currentRowNumber)
      }
    case .unquoted:
      switch byte {
      case Self.quote where fieldBytes.isEmpty:
        try countRowByte()
        fieldState = .quoted
        hasInputSinceRecordSeparator = true
      case Self.quote:
        try countRowByte()
        throw CSVParserError.invalidQuote(row: currentRowNumber)
      case Self.comma:
        try countRowByte()
        try completeField()
        hasInputSinceRecordSeparator = true
      case Self.carriageReturn:
        try completeRecord(headers: &emittedHeaders, rows: &emittedRows)
        shouldSkipLineFeed = true
        hasInputSinceRecordSeparator = false
      case Self.lineFeed:
        try completeRecord(headers: &emittedHeaders, rows: &emittedRows)
        hasInputSinceRecordSeparator = false
      default:
        try countRowByte()
        try appendFieldByte(byte)
        hasInputSinceRecordSeparator = true
      }
    }
  }

  private var currentRowNumber: Int {
    dataRowCount + 1
  }

  private mutating func completeField() throws {
    guard let field = String(bytes: fieldBytes, encoding: .utf8) else {
      throw CSVParserError.invalidUTF8
    }
    record.append(field)
    fieldBytes.removeAll(keepingCapacity: true)
  }

  private mutating func completeRecord(
    headers emittedHeaders: inout [String]?,
    rows emittedRows: inout [[String]]
  ) throws {
    try completeField()

    if let headers {
      let rowNumber = dataRowCount + 1
      guard record.count <= headers.count else {
        throw CSVParserError.rowHasTooManyFields(
          row: rowNumber,
          expected: headers.count,
          actual: record.count
        )
      }
      record.append(contentsOf: repeatElement("", count: headers.count - record.count))
      emittedRows.append(record)
      dataRowCount += 1
    } else {
      self.headers = record
      emittedHeaders = record
    }

    record.removeAll(keepingCapacity: true)
    rowByteCount = 0
  }

  private func validateConfiguration() throws {
    guard limits.isValid else {
      throw CSVParserError.invalidConfiguration
    }
  }

  private mutating func appendFieldByte(_ byte: UInt8) throws {
    guard fieldBytes.count < limits.maximumFieldBytes else {
      throw CSVParserError.fieldTooLarge(
        row: currentRowNumber,
        maximumBytes: limits.maximumFieldBytes
      )
    }
    fieldBytes.append(byte)
  }

  private mutating func countRowByte() throws {
    guard rowByteCount < limits.maximumRowBytes else {
      throw CSVParserError.rowTooLarge(
        row: currentRowNumber,
        maximumBytes: limits.maximumRowBytes
      )
    }
    rowByteCount += 1
  }

  private static let quote = UInt8(ascii: "\"")
  private static let comma = UInt8(ascii: ",")
  private static let carriageReturn = UInt8(ascii: "\r")
  private static let lineFeed = UInt8(ascii: "\n")
}
