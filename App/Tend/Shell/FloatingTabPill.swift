import SwiftUI

struct FloatingTabPill: View {
  let selection: ShellDestination
  let onSelect: (ShellDestination) -> Void

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
      onSelect(destination)
    } label: {
      VStack(spacing: AlmanacMetrics.tabPillInset) {
        icon(for: destination, isSelected: isSelected)
          .font(.system(size: AlmanacMetrics.tabIconSize, weight: .semibold))
          .frame(
            width: AlmanacMetrics.tabIconSize,
            height: AlmanacMetrics.tabIconSize
          )
          .accessibilityHidden(true)

        Text(destination.rawValue.uppercased())
          .font(.caption.weight(.semibold))
          .tracking(0.25)
          .lineLimit(1)
          .minimumScaleFactor(0.8)
          .allowsTightening(true)
      }
      .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
      .foregroundStyle(isSelected ? AlmanacPalette.paper : AlmanacPalette.inkMuted)
      .frame(maxWidth: .infinity)
      .frame(height: AlmanacMetrics.tabItemHeight)
      .contentShape(Capsule())
    }
    .buttonStyle(.plain)
    .background(isSelected ? AlmanacPalette.mossDeep : Color.clear, in: Capsule())
    .accessibilityLabel(destination.rawValue)
    .accessibilityIdentifier(destination.tabAccessibilityIdentifier)
    .accessibilityAddTraits(isSelected ? .isSelected : [])
  }
  private func icon(for destination: ShellDestination, isSelected: Bool) -> Image {
    switch destination {
    case .today:
      AlmanacIcon.today
    case .goals:
      Image(systemName: isSelected ? "flag.fill" : "flag")
    case .habits:
      Image(systemName: "list.bullet")
    case .journal:
      Image(systemName: isSelected ? "book.closed.fill" : "book.closed")
    }
  }
}
