import SwiftUI
import TendCore

struct JournalOverviewView: View {
  @Environment(\.calendar) private var calendar
  @Environment(\.locale) private var locale
  @Environment(\.timeZone) private var timeZone

  let model: JournalOverviewModel
  let onCompose: @MainActor (LocalDate) -> Void
  let onOpenEntry: @MainActor (UUID) -> Void

  var body: some View {
    ZStack(alignment: .topLeading) {
      Group {
        if let failure = model.loadFailure {
          failureSurface(failure)
        } else if let presentation = model.presentation {
          overview(presentation)
        } else {
          Color.clear
            .accessibilityHidden(true)
        }
      }
      .almanacScreen(readableContentWidth: AlmanacMetrics.readableContentWidth)

      Color.clear
        .frame(width: 1, height: 1)
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Journal overview")
        .accessibilityIdentifier("journal.overview")
    }
  }

  private func overview(_ presentation: JournalOverviewPresentation) -> some View {
    ScrollView {
      VStack(alignment: .leading, spacing: AlmanacMetrics.spacingLarge) {
        title
        todayPage(presentation.today)
        pastPages(presentation.pastEntries)
        monthGarden(presentation.month)
      }
      .padding(.bottom, AlmanacMetrics.spacingLarge)
    }
    .scrollDismissesKeyboard(.immediately)
  }

  private var title: some View {
    HStack(spacing: AlmanacMetrics.spacingSmall) {
      Image(systemName: "book.closed.fill")
        .font(.title2.weight(.semibold))
        .foregroundStyle(AlmanacPalette.mossDeep)
        .accessibilityHidden(true)

      Text("Journal")
        .almanacTextStyle(.screenTitle)
        .accessibilityAddTraits(.isHeader)
        .accessibilityIdentifier("journal.title")
    }
  }

  private func todayPage(_ today: JournalTodayPresentation) -> some View {
    let entry = today.writtenEntry
    let day = entry?.day ?? today.unwrittenDay!
    let dateText: String
    let pageTitle: String
    if let entry {
      dateText = entry.dateText
      pageTitle = entry.title
    } else if case .unwritten(_, let unwrittenDateText) = today {
      dateText = unwrittenDateText
      pageTitle = "Write today's page"
    } else {
      preconditionFailure("Journal Today projection must contain one day")
    }

    return Button {
      if let entry {
        onOpenEntry(entry.id)
      } else {
        onCompose(day)
      }
    } label: {
      VStack(alignment: .leading, spacing: AlmanacMetrics.spacingSmall) {
        HStack(spacing: AlmanacMetrics.spacingSmall) {
          Text("TODAY")
            .almanacTextStyle(.emphasizedLabel)
          Spacer(minLength: AlmanacMetrics.spacingSmall)
          Image(systemName: entry == nil ? "square.and.pencil" : "book.pages")
            .foregroundStyle(AlmanacPalette.clayDeep)
            .accessibilityHidden(true)
        }

        Text(pageTitle)
          .font(.system(.title3, design: .serif, weight: .semibold))
          .foregroundStyle(AlmanacPalette.ink)
          .fixedSize(horizontal: false, vertical: true)

        Text(dateText)
          .almanacTextStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      .padding(AlmanacMetrics.spacingLarge)
      .frame(maxWidth: .infinity, minHeight: 128, alignment: .leading)
      .contentShape(
        RoundedRectangle(cornerRadius: AlmanacMetrics.cardRadius, style: .continuous)
      )
    }
    .buttonStyle(.plain)
    .almanacRaisedSurface(radius: AlmanacMetrics.cardRadius)
    .accessibilityLabel(pageTitle)
    .accessibilityValue(dateText)
    .accessibilityHint("Opens the Journal page for today")
    .accessibilityIdentifier("journal.today")
  }

  private func pastPages(_ entries: [JournalOverviewEntry]) -> some View {
    VStack(alignment: .leading, spacing: AlmanacMetrics.spacingMedium) {
      Text("PAST PAGES")
        .almanacTextStyle(.label)
        .accessibilityAddTraits(.isHeader)

      if entries.isEmpty {
        Text("No earlier pages yet.")
          .font(.subheadline)
          .foregroundStyle(AlmanacPalette.inkMuted)
          .fixedSize(horizontal: false, vertical: true)
          .accessibilityIdentifier("journal.past.empty")
      } else {
        LazyVStack(spacing: AlmanacMetrics.spacingSmall) {
          ForEach(entries) { entry in
            Button {
              onOpenEntry(entry.id)
            } label: {
              HStack(alignment: .firstTextBaseline, spacing: AlmanacMetrics.spacingMedium) {
                VStack(alignment: .leading, spacing: AlmanacMetrics.spacingSmall / 2) {
                  Text(entry.title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(AlmanacPalette.ink)
                    .fixedSize(horizontal: false, vertical: true)

                  Text(entry.dateText)
                    .almanacTextStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: AlmanacMetrics.spacingSmall)

                Image(systemName: "chevron.right")
                  .foregroundStyle(AlmanacPalette.inkFaint)
                  .accessibilityHidden(true)
              }
              .padding(AlmanacMetrics.spacingMedium)
              .frame(maxWidth: .infinity, minHeight: AlmanacMetrics.minimumTarget)
              .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .almanacRaisedSurface(radius: AlmanacMetrics.cardRadius)
            .accessibilityLabel(entry.title)
            .accessibilityValue(entry.dateText)
            .accessibilityHint("Opens this Journal page")
            .accessibilityIdentifier("journal.entry.\(entry.id.uuidString)")
          }
        }
      }
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("journal.past")
  }

  private func monthGarden(_ month: JournalMonthProjection) -> some View {
    VStack(alignment: .leading, spacing: AlmanacMetrics.spacingMedium) {
      monthControls(month)
      weekdayHeader

      let items = monthItems(month)
      let rowStarts = Array(stride(from: 0, to: items.count, by: 7))
      ForEach(rowStarts, id: \.self) { rowStart in
        HStack(spacing: 0) {
          ForEach(0..<7, id: \.self) { column in
            monthItem(items[rowStart + column])
            if column != 6 { Spacer(minLength: 0) }
          }
        }
      }
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("journal.month")
  }

  private func monthControls(_ month: JournalMonthProjection) -> some View {
    HStack(spacing: AlmanacMetrics.spacingSmall) {
      monthButton(
        systemImage: "chevron.left",
        label: "Previous month",
        identifier: "journal.month.previous",
        isEnabled: model.canSelectPreviousMonth,
        action: model.selectPreviousMonth
      )

      Text(month.monthTitle.uppercased(with: locale))
        .almanacTextStyle(.emphasizedLabel)
        .frame(maxWidth: .infinity)
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityAddTraits(.isHeader)
        .accessibilityIdentifier("journal.month.title")

      monthButton(
        systemImage: "chevron.right",
        label: "Next month",
        identifier: "journal.month.next",
        isEnabled: model.canSelectNextMonth,
        action: model.selectNextMonth
      )
    }
  }

  private func monthButton(
    systemImage: String,
    label: String,
    identifier: String,
    isEnabled: Bool,
    action: @escaping @MainActor () -> Void
  ) -> some View {
    Button(action: action) {
      Image(systemName: systemImage)
        .font(.body.weight(.semibold))
        .frame(
          width: AlmanacMetrics.minimumTarget,
          height: AlmanacMetrics.minimumTarget
        )
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .foregroundStyle(isEnabled ? AlmanacPalette.inkMuted : AlmanacPalette.hairline)
    .disabled(!isEnabled)
    .accessibilityLabel(label)
    .accessibilityValue(monthTitleAccessibilityValue)
    .accessibilityIdentifier(identifier)
  }

  private var monthTitleAccessibilityValue: String {
    model.presentation?.month.monthTitle ?? "Unavailable"
  }

  private var weekdayHeader: some View {
    let labels = HabitFormWeekday.localizedLabels(calendar: calendar, locale: locale)
    return HStack(spacing: 0) {
      ForEach(labels.indices, id: \.self) { index in
        Text(labels[index].short)
          .font(.caption.weight(.semibold))
          .foregroundStyle(AlmanacPalette.inkMuted)
          .frame(
            width: AlmanacMetrics.minimumTarget,
            height: AlmanacMetrics.minimumTarget
          )
          .accessibilityLabel(labels[index].accessibility)

        if index != labels.indices.last { Spacer(minLength: 0) }
      }
    }
  }

  @ViewBuilder
  private func monthItem(_ item: JournalMonthGridItem) -> some View {
    if let cell = item.cell {
      switch cell.state {
      case .written(let entryID):
        Button {
          onOpenEntry(entryID)
        } label: {
          JournalMonthCellSurface(isWritten: true, isToday: cell.isToday)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(formatted(cell.day))
        .accessibilityValue("Written")
        .accessibilityHint("Opens this Journal page")
        .accessibilityIdentifier("journal.month.day.\(cell.day.rawValue)")
      case .absent:
        JournalMonthCellSurface(isWritten: false, isToday: cell.isToday)
          .accessibilityElement(children: .ignore)
          .accessibilityLabel(formatted(cell.day))
          .accessibilityValue("Not written")
          .accessibilityIdentifier("journal.month.day.\(cell.day.rawValue).absent")
      }
    } else {
      Color.clear
        .frame(
          width: AlmanacMetrics.minimumTarget,
          height: AlmanacMetrics.minimumTarget
        )
        .accessibilityHidden(true)
    }
  }

  private func monthItems(_ month: JournalMonthProjection) -> [JournalMonthGridItem] {
    var result: [JournalMonthGridItem] = []
    result.reserveCapacity(
      month.leadingFillerCount + month.cells.count + month.trailingFillerCount
    )
    for index in 0..<month.leadingFillerCount {
      result.append(JournalMonthGridItem(id: "leading-\(index)", cell: nil))
    }
    result.append(
      contentsOf: month.cells.map {
        JournalMonthGridItem(id: $0.day.rawValue, cell: $0)
      }
    )
    for index in 0..<month.trailingFillerCount {
      result.append(JournalMonthGridItem(id: "trailing-\(index)", cell: nil))
    }
    return result
  }

  private func failureSurface(_ failure: JournalOverviewLoadFailure) -> some View {
    VStack(alignment: .leading, spacing: AlmanacMetrics.spacingLarge) {
      title

      VStack(alignment: .leading, spacing: AlmanacMetrics.spacingMedium) {
        Text(failure.message)
          .font(.body.weight(.semibold))
          .foregroundStyle(AlmanacPalette.ink)
          .fixedSize(horizontal: false, vertical: true)
          .accessibilityIdentifier("journal.failure")

        Button(failure.retryTitle, action: model.retryRefresh)
          .font(.body.weight(.semibold))
          .foregroundStyle(AlmanacPalette.ink)
          .frame(minHeight: AlmanacMetrics.minimumTarget)
          .accessibilityIdentifier("journal.failure.retry")
      }
      .padding(AlmanacMetrics.spacingLarge)
      .frame(maxWidth: .infinity, alignment: .leading)
      .almanacSunkenSurface(radius: AlmanacMetrics.cardRadius)
    }
  }

  private func formatted(_ day: LocalDate) -> String {
    guard let date = try? day.start(in: timeZone) else { return day.rawValue }
    var localCalendar = calendar
    localCalendar.locale = locale
    localCalendar.timeZone = timeZone
    let formatter = DateFormatter()
    formatter.calendar = localCalendar
    formatter.locale = locale
    formatter.timeZone = timeZone
    formatter.setLocalizedDateFormatFromTemplate("EEEE MMMM d yyyy")
    return formatter.string(from: date)
  }
}

private struct JournalMonthGridItem: Identifiable {
  let id: String
  let cell: JournalMonthCell?
}

private struct JournalMonthCellSurface: View {
  let isWritten: Bool
  let isToday: Bool

  var body: some View {
    RoundedRectangle(cornerRadius: AlmanacMetrics.gardenCellRadius, style: .continuous)
      .fill(isWritten ? AlmanacPalette.moss : AlmanacPalette.paperRaised)
      .overlay {
        RoundedRectangle(cornerRadius: AlmanacMetrics.gardenCellRadius, style: .continuous)
          .strokeBorder(
            isToday ? AlmanacPalette.clayDeep : AlmanacPalette.hairline,
            lineWidth: isToday ? AlmanacMetrics.gardenOutlineWidth : 1
          )
      }
      .frame(
        width: AlmanacMetrics.minimumTarget,
        height: AlmanacMetrics.minimumTarget
      )
      .contentShape(
        RoundedRectangle(cornerRadius: AlmanacMetrics.gardenCellRadius, style: .continuous)
      )
  }
}
