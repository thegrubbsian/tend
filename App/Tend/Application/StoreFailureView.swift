import SwiftUI

struct StoreFailureView: View {
  private static let readableContentWidth: CGFloat = 440

  let retry: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: AlmanacMetrics.spacingMedium) {
      Text("Tend couldn't open your garden.")
        .almanacTextStyle(.screenTitle)
        .accessibilityAddTraits(.isHeader)

      Text("Your records were not changed. Try again.")
        .almanacTextStyle(.body)
        .fixedSize(horizontal: false, vertical: true)

      Button("Retry", action: retry)
        .buttonStyle(AlmanacPrimaryButtonStyle())
        .accessibilityIdentifier("startup.retry")
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .almanacScreen(readableContentWidth: Self.readableContentWidth)
    .accessibilityIdentifier("startup.failure")
  }
}
