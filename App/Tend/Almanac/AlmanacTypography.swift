import SwiftUI

enum AlmanacTextStyle {
  case screenTitle
  case body
  case secondary
  case label
  case tabLabel
  case caption
  case meaningfulNumeral(Font.TextStyle)
}

private struct AlmanacTextStyleModifier: ViewModifier {
  let style: AlmanacTextStyle

  @ViewBuilder
  func body(content: Content) -> some View {
    switch style {
    case .screenTitle:
      content
        .font(.system(.title, design: .serif, weight: .semibold))
    case .body:
      content
        .font(.body)
    case .secondary:
      content
        .font(.subheadline)
        .foregroundStyle(AlmanacPalette.inkMuted)
    case .label:
      content
        .font(.footnote.weight(.semibold))
        .textCase(.uppercase)
        .tracking(2.5)
        .foregroundStyle(AlmanacPalette.inkMuted)
    case .tabLabel:
      content
        .font(.caption2.weight(.semibold))
        .textCase(.uppercase)
        .tracking(0.5)
    case .caption:
      content
        .font(.caption)
        .foregroundStyle(AlmanacPalette.inkFaint)
    case .meaningfulNumeral(let relativeStyle):
      content
        .font(.system(relativeStyle, design: .serif, weight: .semibold))
        .monospacedDigit()
    }
  }
}

extension View {
  func almanacTextStyle(_ style: AlmanacTextStyle) -> some View {
    modifier(AlmanacTextStyleModifier(style: style))
  }
}
