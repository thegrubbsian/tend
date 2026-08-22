import SwiftUI

struct JournalDayGardenView: View {
  let rows: [JournalDayGardenPresentationRow]
  let onRetry: @MainActor () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: AlmanacMetrics.spacingMedium) {
      HStack(spacing: AlmanacMetrics.spacingSmall) {
        Image(systemName: "leaf.fill")
          .foregroundStyle(AlmanacPalette.mossDeep)
          .accessibilityHidden(true)

        Text("TODAY'S GARDEN")
          .almanacTextStyle(.emphasizedLabel)
          .accessibilityAddTraits(.isHeader)
          .accessibilityIdentifier("journalGarden.title")
      }

      VStack(spacing: AlmanacMetrics.spacingSmall) {
        ForEach(rows) { row in
          gardenRow(row)
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("journalGarden.section")
  }

  private func gardenRow(_ row: JournalDayGardenPresentationRow) -> some View {
    HStack(alignment: .center, spacing: AlmanacMetrics.spacingMedium) {
      Image(systemName: row.isLeafFilled ? "leaf.fill" : "leaf")
        .font(.title2.weight(.medium))
        .foregroundStyle(color(for: row.tone))
        .frame(width: AlmanacMetrics.minimumTarget)
        .frame(minHeight: AlmanacMetrics.minimumTarget)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(row.stateText) habit state")
        .accessibilityValue(row.isLeafFilled ? "Filled" : "Hollow")
        .accessibilityIdentifier("journalGarden.leaf.\(row.id.uuidString)")

      VStack(alignment: .leading, spacing: AlmanacMetrics.spacingSmall / 2) {
        Text(row.name)
          .font(.body.weight(.semibold))
          .foregroundStyle(AlmanacPalette.ink)
          .fixedSize(horizontal: false, vertical: true)
          .accessibilityIdentifier("journalGarden.name.\(row.id.uuidString)")

        Text(row.progressText)
          .almanacTextStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
          .accessibilityIdentifier("journalGarden.progress.\(row.id.uuidString)")
      }

      Spacer(minLength: AlmanacMetrics.spacingSmall)

      VStack(alignment: .trailing, spacing: AlmanacMetrics.spacingSmall / 2) {
        Text(row.stateText)
          .font(.caption.weight(.semibold))
          .foregroundStyle(deepColor(for: row.tone))
          .fixedSize(horizontal: false, vertical: true)
          .accessibilityIdentifier("journalGarden.state.\(row.id.uuidString)")

        if row.showsRetry {
          Button("Try again", action: onRetry)
            .font(.caption.weight(.semibold))
            .foregroundStyle(AlmanacPalette.ink)
            .frame(
              minWidth: AlmanacMetrics.minimumTarget,
              minHeight: AlmanacMetrics.minimumTarget
            )
            .contentShape(Rectangle())
            .accessibilityIdentifier("journalGarden.retry.\(row.id.uuidString)")
        }
      }
    }
    .padding(AlmanacMetrics.spacingMedium)
    .frame(maxWidth: .infinity, minHeight: AlmanacMetrics.minimumTarget)
    .almanacRaisedSurface(radius: AlmanacMetrics.cardRadius)
    .accessibilityElement(children: .contain)
    .accessibilityLabel(row.name)
    .accessibilityValue(row.accessibilityValue)
    .accessibilityIdentifier("journalGarden.row.\(row.id.uuidString)")
  }

  private func color(for tone: JournalDayGardenTone) -> Color {
    switch tone {
    case .moss: AlmanacPalette.moss
    case .withered: AlmanacPalette.withered
    case .ochre: AlmanacPalette.ochre
    case .dormant: AlmanacPalette.inkFaint
    case .unavailable: AlmanacPalette.clay
    }
  }

  private func deepColor(for tone: JournalDayGardenTone) -> Color {
    switch tone {
    case .moss: AlmanacPalette.mossDeep
    case .withered: AlmanacPalette.inkMuted
    case .ochre: AlmanacPalette.goalOchreDeep
    case .dormant: AlmanacPalette.inkMuted
    case .unavailable: AlmanacPalette.clayDeep
    }
  }
}
