import AppKit
import CoreText
import SwiftUI

enum MailEdgePalette {
  static let blue = Color(red: 0.12, green: 0.42, blue: 0.98)
  static let cyan = Color(red: 0.10, green: 0.78, blue: 0.96)
  static let violet = Color(red: 0.48, green: 0.30, blue: 0.96)
}

struct LiquidBackdrop: View {
  var body: some View {
    Color(nsColor: .windowBackgroundColor)
      .ignoresSafeArea()
  }
}

private struct LiquidGlassModifier: ViewModifier {
  let cornerRadius: CGFloat
  let tint: Color?
  let interactive: Bool

  @ViewBuilder
  func body(content: Content) -> some View {
    if #available(macOS 26.0, *) {
      content.glassEffect(
        .regular.tint(tint).interactive(interactive),
        in: .rect(cornerRadius: cornerRadius)
      )
    } else {
      content
        .background(
          .ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        )
        .overlay {
          RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .strokeBorder(.white.opacity(0.22), lineWidth: 0.8)
        }
        .shadow(color: .black.opacity(0.10), radius: 20, y: 10)
    }
  }
}

extension View {
  func liquidGlass(cornerRadius: CGFloat = 18, tint: Color? = nil, interactive: Bool = false)
    -> some View
  {
    modifier(LiquidGlassModifier(cornerRadius: cornerRadius, tint: tint, interactive: interactive))
  }

  func glassButton(tint: Color? = nil) -> some View {
    buttonStyle(MailEdgeGlassButtonStyle(tint: tint))
  }

  func prominentGlassButton() -> some View {
    buttonStyle(MailEdgeProminentButtonStyle())
  }

  func circularGlassButton(tint: Color? = nil, size: CGFloat = 44) -> some View {
    buttonStyle(MailEdgeCircularButtonStyle(tint: tint, size: size))
  }
}

private struct MailEdgeCircularButtonStyle: ButtonStyle {
  @Environment(\.isEnabled) private var isEnabled
  let tint: Color?
  let size: CGFloat

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.system(size: 15, weight: .semibold))
      .frame(width: size, height: size)
      .contentShape(Circle())
      .scaleEffect(configuration.isPressed ? 0.92 : 1)
      .opacity(isEnabled ? 1 : 0.42)
      .liquidGlass(
        cornerRadius: size / 2,
        tint: tint,
        interactive: isEnabled
      )
      .animation(.snappy(duration: 0.18), value: configuration.isPressed)
      .animation(.easeOut(duration: 0.16), value: isEnabled)
  }
}

private struct MailEdgeGlassButtonStyle: ButtonStyle {
  @Environment(\.isEnabled) private var isEnabled
  let tint: Color?

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.callout.weight(.semibold))
      .frame(minHeight: 44)
      .padding(.horizontal, 12)
      .contentShape(Capsule())
      .opacity(isEnabled ? 1 : 0.45)
      .scaleEffect(configuration.isPressed ? 0.96 : 1)
      .modifier(
        LiquidButtonSurface(
          tint: tint,
          prominent: false,
          interactive: isEnabled,
          pressed: configuration.isPressed
        )
      )
      .animation(.snappy(duration: 0.2), value: configuration.isPressed)
  }
}

private struct MailEdgeProminentButtonStyle: ButtonStyle {
  @Environment(\.isEnabled) private var isEnabled

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.callout.weight(.semibold))
      .foregroundStyle(isEnabled ? Color.white : Color.secondary)
      .frame(minHeight: 44)
      .padding(.horizontal, 16)
      .contentShape(Capsule())
      .scaleEffect(configuration.isPressed ? 0.975 : 1)
      .modifier(
        LiquidButtonSurface(
          tint: isEnabled ? MailEdgePalette.blue : Color.secondary.opacity(0.08),
          prominent: true,
          interactive: isEnabled,
          pressed: configuration.isPressed
        )
      )
      .animation(.snappy(duration: 0.22), value: configuration.isPressed)
      .animation(.easeOut(duration: 0.18), value: isEnabled)
  }
}

private struct LiquidButtonSurface: ViewModifier {
  let tint: Color?
  let prominent: Bool
  let interactive: Bool
  let pressed: Bool

  @ViewBuilder
  func body(content: Content) -> some View {
    if #available(macOS 26.0, *) {
      content
        .glassEffect(
          .regular.tint(tint).interactive(interactive),
          in: .capsule
        )
        .brightness(pressed ? -0.05 : 0)
    } else {
      content
        .background(
          prominent ? MailEdgePalette.blue.opacity(pressed ? 0.78 : 0.94) : Color.clear,
          in: Capsule()
        )
        .background(.ultraThinMaterial, in: Capsule())
        .overlay {
          Capsule().strokeBorder(.white.opacity(prominent ? 0.28 : 0.18), lineWidth: 0.8)
        }
        .shadow(
          color: prominent ? MailEdgePalette.blue.opacity(0.20) : .black.opacity(0.08),
          radius: pressed ? 3 : 8,
          y: pressed ? 1 : 4
        )
    }
  }
}

struct MailEdgeMark: View {
  var size: CGFloat = 44

  var body: some View {
    Group {
      if let image = MailEdgeBrand.logoImage() {
        Image(nsImage: image)
          .resizable()
          .interpolation(.high)
          .aspectRatio(contentMode: .fit)
      } else {
        Color.clear
      }
    }
    .frame(width: size, height: size)
    .shadow(color: MailEdgePalette.blue.opacity(0.18), radius: size * 0.18, y: size * 0.08)
    .accessibilityHidden(true)
  }
}

struct MailEdgeWordmark: View {
  var size: CGFloat = 20
  var weight: Font.Weight = .semibold

  var body: some View {
    Text("MailEdge")
      .font(MailEdgeBrand.wordmarkFont(size: size, weight: weight))
      .tracking(-size * 0.02)
      .lineLimit(1)
  }
}

enum MailEdgeBrand {
  static let fontFamilyName = "Stack Sans Notch"
  @MainActor private static var didRegisterFonts = false

  @MainActor
  static func registerFonts() {
    guard !didRegisterFonts else { return }
    didRegisterFonts = true
    let url =
      Bundle.module.url(
        forResource: "StackSansNotch-Variable", withExtension: "ttf", subdirectory: "Fonts")
      ?? Bundle.module.url(forResource: "StackSansNotch-Variable", withExtension: "ttf")
    guard let url else { return }
    CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
  }

  @MainActor
  static func wordmarkFont(size: CGFloat, weight: Font.Weight = .semibold) -> Font {
    registerFonts()
    return .custom(fontFamilyName, fixedSize: size).weight(weight)
  }

  @MainActor
  static func logoImage() -> NSImage? {
    guard let url = Bundle.module.url(forResource: "AppIcon", withExtension: "png") else {
      return nil
    }
    return NSImage(contentsOf: url)
  }
}
