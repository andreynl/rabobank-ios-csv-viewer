struct CSVResourceLimits: Equatable, Sendable {
  static let `default` = CSVResourceLimits(
    maximumFieldBytes: 1 * 1024 * 1024,
    maximumRowBytes: 4 * 1024 * 1024,
    maximumPageBytes: 8 * 1024 * 1024
  )

  let maximumFieldBytes: Int
  let maximumRowBytes: Int
  let maximumPageBytes: Int

  var isValid: Bool {
    maximumFieldBytes > 0
      && maximumRowBytes > 0
      && maximumPageBytes > 0
      && maximumFieldBytes <= maximumRowBytes
      && maximumRowBytes <= maximumPageBytes
  }
}
