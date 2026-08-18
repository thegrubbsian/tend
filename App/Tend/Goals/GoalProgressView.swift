import SwiftUI
import TendCore

struct GoalProgressView: View {
  let progress: GoalDetailProgressFact
  let progressText: String
  let standing: GoalStanding?
  let expectedNormalizedProgress: Double?
  let standingText: String?
  let closure: GoalClosure?
  let closureText: String?

  init(
    progress: GoalDetailProgressFact,
    progressText: String,
    standing: GoalStanding? = nil,
    expectedNormalizedProgress: Double? = nil,
    standingText: String? = nil,
    closure: GoalClosure? = nil,
    closureText: String? = nil
  ) {
    self.progress = progress
    self.progressText = progressText
    self.standing = standing
    self.expectedNormalizedProgress = expectedNormalizedProgress
    self.standingText = standingText
    self.closure = closure
    self.closureText = closureText
  }

  var body: some View {
    VStack(alignment: .leading, spacing: AlmanacMetrics.spacingMedium) {
      progressSummary

      if let statusStyle {
        statusLabel(statusStyle)
      }

      kindSpecificProgress
    }
    .padding(AlmanacMetrics.spacingMedium)
    .frame(maxWidth: .infinity, alignment: .leading)
    .almanacRaisedSurface()
    .accessibilityElement(children: .contain)
  }

  private var progressSummary: some View {
    VStack(alignment: .leading, spacing: AlmanacMetrics.spacingSmall) {
      Text("Progress")
        .almanacTextStyle(.label)

      Text(progressText)
        .almanacTextStyle(.meaningfulNumeral(.title2))
        .foregroundStyle(AlmanacPalette.ink)
        .fixedSize(horizontal: false, vertical: true)
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("Progress")
    .accessibilityValue(progressText)
  }

  @ViewBuilder
  private var kindSpecificProgress: some View {
    switch progress {
    case .accumulate(_, _, _, let normalizedProgress):
      progressTrack(
        normalizedProgress: normalizedProgress,
        orientation: .leadingToTrailing,
        showsCurrentMarker: false
      )
    case .measure(
      let baseline,
      let target,
      _,
      _,
      _,
      let direction,
      let unit,
      let normalizedProgress
    ):
      measureProgress(
        baseline: baseline,
        target: target,
        direction: direction,
        unit: unit,
        normalizedProgress: normalizedProgress
      )
    }
  }

  private func measureProgress(
    baseline: Int,
    target: Int,
    direction: GoalDetailMeasureDirection,
    unit: String,
    normalizedProgress: Double
  ) -> some View {
    VStack(alignment: .leading, spacing: AlmanacMetrics.spacingSmall) {
      directionLabel(direction)
      measureEndpoints(
        baseline: baseline,
        target: target,
        direction: direction,
        unit: unit
      )
      progressTrack(
        normalizedProgress: normalizedProgress,
        orientation: trackOrientation(for: direction),
        showsCurrentMarker: true
      )
    }
  }

  private func progressTrack(
    normalizedProgress: Double,
    orientation: GoalProgressTrack.Orientation,
    showsCurrentMarker: Bool
  ) -> some View {
    VStack(alignment: .leading, spacing: AlmanacMetrics.spacingSmall) {
      GoalProgressTrack(
        normalizedProgress: normalizedProgress,
        expectedNormalizedProgress: expectedNormalizedProgress,
        orientation: orientation,
        showsCurrentMarker: showsCurrentMarker,
        accent: progressColor
      )

      if let expectedNormalizedProgress {
        paceLabel(expectedNormalizedProgress)
      }
    }
  }

  private func directionLabel(_ direction: GoalDetailMeasureDirection) -> some View {
    HStack(spacing: AlmanacMetrics.spacingSmall / 2) {
      Image(systemName: direction == .increasing ? "arrow.right" : "arrow.left")
        .accessibilityHidden(true)

      Text(direction == .increasing ? "Increasing measure" : "Decreasing measure")
        .fixedSize(horizontal: false, vertical: true)
    }
    .almanacTextStyle(.caption)
    .accessibilityElement(children: .combine)
  }

  @ViewBuilder
  private func measureEndpoints(
    baseline: Int,
    target: Int,
    direction: GoalDetailMeasureDirection,
    unit: String
  ) -> some View {
    HStack(alignment: .top, spacing: AlmanacMetrics.spacingMedium) {
      if direction == .increasing {
        endpointLabel(
          title: "Baseline",
          value: baseline,
          unit: unit,
          horizontalAlignment: .leading,
          frameAlignment: .leading,
          textAlignment: .leading
        )
        endpointLabel(
          title: "Target",
          value: target,
          unit: unit,
          horizontalAlignment: .trailing,
          frameAlignment: .trailing,
          textAlignment: .trailing
        )
      } else {
        endpointLabel(
          title: "Target",
          value: target,
          unit: unit,
          horizontalAlignment: .leading,
          frameAlignment: .leading,
          textAlignment: .leading
        )
        endpointLabel(
          title: "Baseline",
          value: baseline,
          unit: unit,
          horizontalAlignment: .trailing,
          frameAlignment: .trailing,
          textAlignment: .trailing
        )
      }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(
      Text(
        "Baseline \(baseline, format: .number) \(unit), target \(target, format: .number) \(unit)"
      )
    )
  }

  private func endpointLabel(
    title: String,
    value: Int,
    unit: String,
    horizontalAlignment: HorizontalAlignment,
    frameAlignment: Alignment,
    textAlignment: TextAlignment
  ) -> some View {
    VStack(alignment: horizontalAlignment, spacing: AlmanacMetrics.spacingSmall / 2) {
      Text(title)
        .almanacTextStyle(.label)

      Text("\(value, format: .number) \(unit)")
        .almanacTextStyle(.meaningfulNumeral(.body))
        .foregroundStyle(AlmanacPalette.ink)
        .multilineTextAlignment(textAlignment)
        .fixedSize(horizontal: false, vertical: true)
    }
    .frame(maxWidth: .infinity, alignment: frameAlignment)
    .accessibilityElement(children: .combine)
  }

  private func statusLabel(_ style: GoalProgressStatusStyle) -> some View {
    HStack(spacing: AlmanacMetrics.spacingSmall) {
      Circle()
        .fill(style.accent)
        .frame(
          width: AlmanacMetrics.spacingSmall,
          height: AlmanacMetrics.spacingSmall
        )
        .accessibilityHidden(true)

      Text(style.text)
        .almanacTextStyle(.secondary)
        .fontWeight(.semibold)
        .foregroundStyle(AlmanacPalette.ink)
        .fixedSize(horizontal: false, vertical: true)
    }
    .accessibilityElement(children: .combine)
  }

  private func paceLabel(_ expectedNormalizedProgress: Double) -> some View {
    HStack(spacing: AlmanacMetrics.spacingSmall) {
      Capsule()
        .fill(AlmanacPalette.inkMuted)
        .frame(
          width: AlmanacMetrics.gardenOutlineWidth,
          height: AlmanacMetrics.spacingMedium
        )
        .accessibilityHidden(true)

      Text("Expected pace")
        .almanacTextStyle(.caption)
        .fixedSize(horizontal: false, vertical: true)
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("Expected pace marker")
    .accessibilityValue(Text(expectedNormalizedProgress, format: .percent))
  }

  private var progressColor: Color {
    statusStyle?.accent ?? AlmanacPalette.moss
  }

  private var statusStyle: GoalProgressStatusStyle? {
    if let closure, let closureText {
      switch closure {
      case .harvested:
        return GoalProgressStatusStyle(
          text: closureText,
          accent: AlmanacPalette.moss
        )
      case .letGo:
        return GoalProgressStatusStyle(
          text: closureText,
          accent: AlmanacPalette.withered
        )
      }
    }

    guard let standing, let standingText else { return nil }
    switch standing {
    case .onPace:
      return GoalProgressStatusStyle(
        text: standingText,
        accent: AlmanacPalette.moss
      )
    case .behind:
      return GoalProgressStatusStyle(
        text: standingText,
        accent: AlmanacPalette.ochre
      )
    case .pastDue:
      return GoalProgressStatusStyle(
        text: standingText,
        accent: AlmanacPalette.clay
      )
    }
  }

  private func trackOrientation(
    for direction: GoalDetailMeasureDirection
  ) -> GoalProgressTrack.Orientation {
    switch direction {
    case .increasing:
      .leadingToTrailing
    case .decreasing:
      .trailingToLeading
    }
  }
}

private struct GoalProgressStatusStyle {
  let text: String
  let accent: Color
}

private struct GoalProgressTrack: View {
  enum Orientation {
    case leadingToTrailing
    case trailingToLeading
  }

  @Environment(\.layoutDirection) private var layoutDirection

  let normalizedProgress: Double
  let expectedNormalizedProgress: Double?
  let orientation: Orientation
  let showsCurrentMarker: Bool
  let accent: Color

  var body: some View {
    GeometryReader { geometry in
      let trackWidth = geometry.size.width
      let progress = clamped(normalizedProgress)

      ZStack {
        Capsule()
          .fill(AlmanacPalette.paperSunken)
          .frame(height: AlmanacMetrics.spacingSmall)

        Capsule()
          .fill(accent)
          .frame(
            width: trackWidth * progress,
            height: AlmanacMetrics.spacingSmall
          )
          .frame(maxWidth: .infinity, alignment: fillAlignment)

        if let expectedNormalizedProgress {
          paceTick(
            fraction: clamped(expectedNormalizedProgress),
            size: geometry.size
          )
        }

        if showsCurrentMarker {
          currentMarker(fraction: progress, size: geometry.size)
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .frame(height: AlmanacMetrics.spacingLarge)
    .accessibilityHidden(true)
  }

  private var fillAlignment: Alignment {
    switch orientation {
    case .leadingToTrailing:
      .leading
    case .trailingToLeading:
      .trailing
    }
  }

  private func paceTick(fraction: CGFloat, size: CGSize) -> some View {
    Capsule()
      .fill(AlmanacPalette.inkMuted)
      .frame(
        width: AlmanacMetrics.gardenOutlineWidth,
        height: AlmanacMetrics.spacingLarge
      )
      .position(
        x: centerX(
          for: fraction,
          width: size.width,
          itemWidth: AlmanacMetrics.gardenOutlineWidth
        ),
        y: size.height / 2
      )
  }

  private func currentMarker(fraction: CGFloat, size: CGSize) -> some View {
    Circle()
      .fill(AlmanacPalette.paperRaised)
      .overlay {
        Circle()
          .strokeBorder(
            accent,
            lineWidth: AlmanacMetrics.gardenOutlineWidth
          )
      }
      .frame(
        width: AlmanacMetrics.spacingMedium,
        height: AlmanacMetrics.spacingMedium
      )
      .position(
        x: centerX(
          for: fraction,
          width: size.width,
          itemWidth: AlmanacMetrics.spacingMedium
        ),
        y: size.height / 2
      )
  }

  private func centerX(
    for fraction: CGFloat,
    width: CGFloat,
    itemWidth: CGFloat
  ) -> CGFloat {
    let physicalX = directedPhysicalX(for: fraction, width: width)
    let edgeInset = min(itemWidth / 2, width / 2)
    return min(max(physicalX, edgeInset), width - edgeInset)
  }

  private func directedPhysicalX(
    for fraction: CGFloat,
    width: CGFloat
  ) -> CGFloat {
    switch orientation {
    case .leadingToTrailing:
      layoutDirection == .leftToRight
        ? width * fraction
        : width * (1 - fraction)
    case .trailingToLeading:
      layoutDirection == .leftToRight
        ? width * (1 - fraction)
        : width * fraction
    }
  }

  private func clamped(_ fraction: Double) -> CGFloat {
    CGFloat(min(max(fraction, 0), 1))
  }
}
