import SwiftUI

private struct AlmanacRaisedSurfaceModifier: ViewModifier {
  let radius: CGFloat

  func body(content: Content) -> some View {
    content
      .background {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
          .fill(AlmanacPalette.paperRaised)
      }
      .overlay {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
          .strokeBorder(AlmanacPalette.hairline, lineWidth: 1)
      }
  }
}

private struct AlmanacSunkenSurfaceModifier: ViewModifier {
  let radius: CGFloat

  func body(content: Content) -> some View {
    content
      .background {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
          .fill(AlmanacPalette.paperSunken)
      }
  }
}

private struct AlmanacScreenModifier: ViewModifier {
  let readableContentWidth: CGFloat?

  func body(content: Content) -> some View {
    ZStack(alignment: .top) {
      AlmanacPalette.paper
        .ignoresSafeArea()

      content
        .padding(.horizontal, AlmanacMetrics.screenPadding)
        .padding(.top, AlmanacMetrics.spacingSmall)
        .frame(
          maxWidth: readableContentWidth ?? .infinity,
          maxHeight: .infinity,
          alignment: .topLeading
        )
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .foregroundStyle(AlmanacPalette.ink)
  }
}

struct AlmanacPrimaryButtonStyle: ButtonStyle {
  let minimumTarget: CGFloat

  init(minimumTarget: CGFloat = AlmanacMetrics.minimumTarget) {
    self.minimumTarget = minimumTarget
  }

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.body.weight(.semibold))
      .foregroundStyle(AlmanacPalette.paper)
      .frame(
        minWidth: minimumTarget,
        minHeight: minimumTarget
      )
      .padding(.horizontal, AlmanacMetrics.spacingLarge)
      .background(
        configuration.isPressed ? AlmanacPalette.mossDeep : AlmanacPalette.moss,
        in: Capsule()
      )
      .contentShape(Capsule())
  }
}

extension View {
  func almanacRaisedSurface(radius: CGFloat = AlmanacMetrics.cardRadius) -> some View {
    modifier(AlmanacRaisedSurfaceModifier(radius: radius))
  }

  func almanacSunkenSurface(radius: CGFloat = AlmanacMetrics.insetRadius) -> some View {
    modifier(AlmanacSunkenSurfaceModifier(radius: radius))
  }

  func almanacScreen(readableContentWidth: CGFloat? = nil) -> some View {
    modifier(AlmanacScreenModifier(readableContentWidth: readableContentWidth))
  }
}
