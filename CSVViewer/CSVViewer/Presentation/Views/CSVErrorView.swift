import SwiftUI

struct CSVErrorView: View {
  let message: String
  let onRetry: (() -> Void)?

  init(message: String, onRetry: (() -> Void)? = nil) {
    self.message = message
    self.onRetry = onRetry
  }

  var body: some View {
    VStack(spacing: 16) {
      ContentUnavailableView(
        "Unable to Open CSV",
        systemImage: "exclamationmark.triangle",
        description: Text(message)
      )
      .accessibilityIdentifier("csvErrorState")
      if let onRetry {
        Button("Retry", action: onRetry)
          .buttonStyle(.borderedProminent)
          .accessibilityIdentifier("retryCSVLoadButton")
      }
    }
  }
}
