import Synchronization

final class CSVLoadSession: Sendable {
  let updates: AsyncThrowingStream<CSVLoadProgress, Error>
  let pages: any CSVPageProviding

  private let cancellationState = Mutex(false)
  private let onCancel: @Sendable () -> Void

  init(
    updates: AsyncThrowingStream<CSVLoadProgress, Error>,
    pages: any CSVPageProviding,
    onCancel: @escaping @Sendable () -> Void
  ) {
    self.updates = updates
    self.pages = pages
    self.onCancel = onCancel
  }

  deinit {
    cancel()
  }

  func cancel() {
    let shouldCancel = cancellationState.withLock { isCancelled in
      guard !isCancelled else { return false }
      isCancelled = true
      return true
    }

    if shouldCancel {
      onCancel()
    }
  }
}
