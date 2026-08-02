import SwiftUI

struct StoreFailureView: View {
  let retry: () -> Void

  var body: some View {
    VStack(spacing: 16) {
      Text("Tend couldn't open your garden.")
        .font(.title)
        .accessibilityAddTraits(.isHeader)

      Text("Your records were not changed. Try again.")
        .multilineTextAlignment(.center)

      Button(action: retry) {
        Text("Retry")
          .frame(minWidth: 44, minHeight: 44)
      }
      .accessibilityIdentifier("startup.retry")
    }
    .padding(24)
    .accessibilityIdentifier("startup.failure")
  }
}
