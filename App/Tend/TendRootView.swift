import SwiftUI

struct TendRootView: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("Today")
        .almanacTextStyle(.screenTitle)

      Spacer(minLength: 0)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .almanacScreen()
    .accessibilityIdentifier("today.screen")
  }
}
