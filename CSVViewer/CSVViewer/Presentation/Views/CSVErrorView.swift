import SwiftUI

struct CSVErrorView: View {
  let message: String

  var body: some View {
    ContentUnavailableView(
      "Unable to Open CSV",
      systemImage: "exclamationmark.triangle",
      description: Text(message)
    )
    .accessibilityIdentifier("csvErrorState")
  }
}
