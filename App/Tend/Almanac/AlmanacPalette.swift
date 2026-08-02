import SwiftUI

private struct AlmanacSRGB {
  private static let componentScale = 255.0

  let red: Double
  let green: Double
  let blue: Double

  init(_ hexadecimal: UInt32) {
    red = Double((hexadecimal >> 16) & 0xFF) / Self.componentScale
    green = Double((hexadecimal >> 8) & 0xFF) / Self.componentScale
    blue = Double(hexadecimal & 0xFF) / Self.componentScale
  }

  var color: Color {
    Color(.sRGB, red: red, green: green, blue: blue, opacity: 1)
  }
}

enum AlmanacPalette {
  static let paper = color(0xF7F2E7)
  static let paperRaised = color(0xFCF9F1)
  static let paperSunken = color(0xEDE6D6)

  static let ink = color(0x2B2A26)
  static let inkMuted = color(0x6F6A5E)
  static let inkFaint = color(0xA79F8F)
  static let hairline = color(0xE6DEC9)

  static let moss = color(0x3D5A3D)
  static let mossDeep = color(0x2F462F)
  static let clay = color(0xC1704F)
  static let clayDeep = color(0xA4573C)
  static let ochre = color(0xD9A441)
  static let ochreDeep = color(0x9C7414)
  static let withered = color(0x8A6A52)

  private static func color(_ hexadecimal: UInt32) -> Color {
    AlmanacSRGB(hexadecimal).color
  }
}
