import SwiftUI

struct FloatingTabPill: View {
  @Binding var selection: ShellDestination

  var body: some View {
    HStack(spacing: AlmanacMetrics.tabPillInset) {
      ForEach(ShellDestination.allCases) { destination in
        tabButton(for: destination)
      }
    }
    .padding(AlmanacMetrics.tabPillInset)
    .frame(maxWidth: .infinity)
    .frame(height: AlmanacMetrics.tabPillHeight)
    .almanacRaisedSurface(radius: AlmanacMetrics.tabPillRadius)
  }

  private func tabButton(for destination: ShellDestination) -> some View {
    let isSelected = selection == destination

    return Button {
      selection = destination
    } label: {
      VStack(spacing: AlmanacMetrics.tabPillInset) {
        icon(for: destination)
          .font(.system(size: AlmanacMetrics.tabIconSize, weight: .semibold))
          .frame(
            width: AlmanacMetrics.tabIconSize,
            height: AlmanacMetrics.tabIconSize
          )

        Text(destination.rawValue)
          .almanacTextStyle(.tabLabel)
          .lineLimit(1)
          .fixedSize(horizontal: true, vertical: false)
      }
      .foregroundStyle(isSelected ? AlmanacPalette.paper : AlmanacPalette.inkFaint)
      .frame(maxWidth: .infinity)
      .frame(height: AlmanacMetrics.tabItemHeight)
      .background(isSelected ? AlmanacPalette.moss : Color.clear, in: Capsule())
      .contentShape(Capsule())
    }
    .buttonStyle(.plain)
    .accessibilityLabel(destination.rawValue)
    .accessibilityIdentifier(destination.tabAccessibilityIdentifier)
    .accessibilityAddTraits(isSelected ? .isSelected : [])
  }

  private func icon(for destination: ShellDestination) -> Image {
    switch destination {
    case .today:
      AlmanacIcon.today
    case .habits:
      Image(systemName: "list.bullet")
    }
  }
}
