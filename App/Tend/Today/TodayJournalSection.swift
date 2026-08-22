import SwiftUI
import TendCore

struct TodayJournalSection: View {
  let invitation: TodayJournalInvitation
  let openJournal: (LocalDate) -> Void
  let retry: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: AlmanacMetrics.spacingSmall) {
      Text("JOURNAL").almanacTextStyle(.label)
        .foregroundStyle(AlmanacPalette.inkMuted)
        .accessibilityIdentifier("today.section.journal")
        .accessibilityAddTraits(.isHeader)

      switch invitation {
      case .invitation(let day):
        invitationCard(day: day)
      case .unavailable(let failure):
        unavailableCard(failure)
      case .complete:
        EmptyView()
      }
    }
  }

  private func invitationCard(day: LocalDate) -> some View {
    Button {
      openJournal(day)
    } label: {
      HStack(alignment: .center, spacing: AlmanacMetrics.spacingMedium) {
        VStack(alignment: .leading, spacing: AlmanacMetrics.spacingSmall) {
          Text("Write today’s page")
            .font(.headline.weight(.semibold))
            .foregroundStyle(AlmanacPalette.ink)
            .fixedSize(horizontal: false, vertical: true)

          Text("Gather a few lines from the day while they’re fresh.")
            .almanacTextStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }

        Spacer(minLength: AlmanacMetrics.spacingSmall)

        Image(systemName: "book.closed")
          .font(.title3.weight(.medium))
          .foregroundStyle(AlmanacPalette.clayDeep)
          .accessibilityHidden(true)
      }
      .padding(AlmanacMetrics.spacingMedium)
      .padding(.leading, AlmanacMetrics.spacingSmall)
      .frame(
        maxWidth: .infinity,
        minHeight: AlmanacMetrics.minimumTarget,
        alignment: .leading
      )
      .contentShape(
        RoundedRectangle(cornerRadius: AlmanacMetrics.cardRadius, style: .continuous)
      )
      .overlay(alignment: .leading) {
        RoundedRectangle(cornerRadius: 2, style: .continuous)
          .fill(AlmanacPalette.clayDeep)
          .frame(width: 3)
          .padding(.vertical, AlmanacMetrics.spacingMedium)
          .padding(.leading, AlmanacMetrics.spacingMedium)
          .accessibilityHidden(true)
      }
    }
    .buttonStyle(.plain)
    .almanacRaisedSurface()
    .accessibilityElement(children: .ignore)
    .accessibilityAddTraits(.isButton)
    .accessibilityLabel("Write today's Journal entry")
    .accessibilityValue("Gather a few lines from the day while they’re fresh.")
    .accessibilityHint("Opens today's page in Journal.")
    .accessibilityIdentifier("today.journal.write")
  }

  private func unavailableCard(_ failure: TodayJournalFailure) -> some View {
    VStack(alignment: .leading, spacing: AlmanacMetrics.spacingMedium) {
      Text(failure.message)
        .almanacTextStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityIdentifier("today.journal.failure")

      Button(action: retry) {
        Text(failure.retryTitle)
          .font(.body.weight(.semibold))
          .foregroundStyle(AlmanacPalette.clayDeep)
          .frame(minHeight: AlmanacMetrics.minimumTarget)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityHint("Retries the Journal invitation.")
      .accessibilityIdentifier("today.journal.retry")
    }
    .padding(AlmanacMetrics.spacingMedium)
    .padding(.leading, AlmanacMetrics.spacingSmall)
    .frame(maxWidth: .infinity, alignment: .leading)
    .overlay(alignment: .leading) {
      RoundedRectangle(cornerRadius: 2, style: .continuous)
        .fill(AlmanacPalette.clayDeep)
        .frame(width: 3)
        .padding(.vertical, AlmanacMetrics.spacingMedium)
        .padding(.leading, AlmanacMetrics.spacingMedium)
        .accessibilityHidden(true)
    }
    .almanacRaisedSurface()
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("today.journal.card")
  }
}
