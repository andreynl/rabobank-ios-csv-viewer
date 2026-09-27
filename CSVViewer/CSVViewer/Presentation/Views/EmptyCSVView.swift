import SwiftUI

struct EmptyCSVView: View {
  var body: some View {
    ContentUnavailableView(
      "Empty CSV",
      systemImage: "tablecells",
      description: Text("Choose another file that contains a header row.")
    )
    .accessibilityIdentifier("csvEmptyState")
  }
}
