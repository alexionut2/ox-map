import SwiftUI
import UIKit
import OxydeCore

// MARK: Colors

extension Color {
    init(hex: HexColor) {
        self.init(.sRGB, red: hex.red, green: hex.green, blue: hex.blue, opacity: hex.alpha)
    }
}

extension UIColor {
    convenience init(hex: HexColor) {
        self.init(red: hex.red, green: hex.green, blue: hex.blue, alpha: hex.alpha)
    }
}

extension HexColor {
    init(_ color: Color) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        self.init(red: Double(r), green: Double(g), blue: Double(b), alpha: Double(a))
    }
}

/// Brand tokens from oxyde.ro: deep ink surfaces, hairline borders, violet brand and a
/// lavender accent. Map and accent colors still come from the active theme.
enum OX {
    static let ink = Color(hex: "#14121A")
    static let surface = Color(hex: "#1B1824")
    static let surface2 = Color(hex: "#232030")
    static let line = Color(hex: "#332F42")
    static let line2 = Color(hex: "#4A4560")
    static let text = Color(hex: "#F3F1F8")
    static let muted = Color(hex: "#B3AEC4")
    static let brand = Color(hex: "#7C4DFF")
    static let lavender = Color(hex: "#B49CFF")
    static let ok = Color(hex: "#5AD39A")
    static let error = Color(hex: "#FF7A8C")
    static let warning = Color(hex: "#F2C14E")

    // Older names, kept so every screen picks up the new palette.
    static let black = ink
    static let graphite = surface
    static let graphiteRaised = surface2
    static let metal = muted
    static let hairline = line

    /// The site's signature gradient.
    static let gradient = LinearGradient(colors: [lavender, brand], startPoint: .leading, endPoint: .trailing)

    /// Accent presets offered in Settings.
    static let accents: [(name: String, hex: HexColor)] = [
        ("Oxyde Violet", "#7C4DFF"), ("Lavender", "#B49CFF"), ("Electric Blue", "#2F7BFF"), ("Cyan", "#00E0FF"),
        ("Red", "#FF2D3D"), ("Lime", "#B6FF00"), ("Orange", "#FF7A00"), ("White", "#F4F6F8"),
    ]

    static let corner: CGFloat = 18
    static let radiusLarge: CGFloat = 12
    static let radiusSmall: CGFloat = 8
    static let gutter: CGFloat = 16
}

// MARK: Typography

extension TypographyStyle {
    func font(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        switch self {
        case .standard: return .system(size: size, weight: weight, design: .default)
        case .rounded: return .system(size: size, weight: weight, design: .rounded)
        case .technical: return .system(size: size, weight: weight, design: .monospaced)
        case .sport: return .system(size: size, weight: .heavy, design: .default).width(.condensed)
        }
    }
}

// MARK: Panels

struct PanelBackground: ViewModifier {
    var style: PanelStyle
    var cornerRadius: CGFloat = OX.corner

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(style == .glass ? AnyShapeStyle(.ultraThinMaterial) : AnyShapeStyle(OX.surface.opacity(0.97)))
                    .overlay {
                        if style == .glass {
                            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).fill(OX.surface.opacity(0.45))
                        }
                    }
                    .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).strokeBorder(OX.line))
                    .shadow(color: .black.opacity(0.35), radius: 18, y: 8)
            }
    }
}

extension View {
    func oxPanel(_ style: PanelStyle = .glass, cornerRadius: CGFloat = OX.corner) -> some View {
        modifier(PanelBackground(style: style, cornerRadius: cornerRadius))
    }
}

/// Round floating map control.
struct FloatingButton: View {
    let symbol: String
    var label: String
    var isActive = false
    var size: CGFloat = 48
    let action: () -> Void
    @Environment(AppModel.self) private var model

    var body: some View {
        Button {
            model.haptics.tap(enabled: model.settings.value.hapticsEnabled)
            action()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: size * 0.38, weight: .semibold))
                .foregroundStyle(isActive ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
                .frame(width: size, height: size)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .oxPanel(model.activeTheme.interface.panel, cornerRadius: size / 2)
        .accessibilityLabel(label)
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        let accent = MainActor.assumeIsolated {
            AppModel.shared.settings.value.accentOverride ?? AppModel.shared.activeTheme.interface.accent
        }
        // Light accents get dark text, dark accents white text, like the site's buttons.
        let text: Color = HexColor.contrast(accent, "#FFFFFF") >= 3 ? .white : .black
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(.tint, in: RoundedRectangle(cornerRadius: OX.radiusLarge, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: OX.radiusLarge, style: .continuous)
                .fill(LinearGradient(colors: [.white.opacity(0.18), .clear], startPoint: .top, endPoint: .bottom)))
            .foregroundStyle(text)
            .shadow(color: Color.accentColor.opacity(configuration.isPressed ? 0.1 : 0.35), radius: 14, y: 6)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(duration: 0.2), value: configuration.isPressed)
    }
}

/// Cards lift slightly when touched, like the site's hover effect.
struct OxCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .offset(y: configuration.isPressed ? -2 : 0)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// A bordered surface card in the oxyde.ro style.
struct OxCard: ViewModifier {
    var padding: CGFloat = 14
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(OX.surface, in: RoundedRectangle(cornerRadius: OX.radiusLarge, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: OX.radiusLarge, style: .continuous).strokeBorder(OX.line))
    }
}

extension View {
    func oxCard(padding: CGFloat = 14) -> some View { modifier(OxCard(padding: padding)) }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(OX.surface2, in: RoundedRectangle(cornerRadius: OX.radiusLarge, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: OX.radiusLarge, style: .continuous).strokeBorder(OX.line2))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
    }
}

/// A capability badge used in Map Studio so the user always sees what a control affects.
struct SupportBadge: View {
    let support: PropertySupport
    var body: some View {
        switch support {
        case .supported: EmptyView()
        case .partial(let note):
            Label("Partial", systemImage: "circle.lefthalf.filled").font(.caption2).foregroundStyle(.secondary).help(note)
        case .unsupported:
            Label("Vector engine", systemImage: "square.3.layers.3d").font(.caption2).foregroundStyle(.orange)
        }
    }
}

// MARK: Haptics

@MainActor
final class Haptics {
    private let light = UIImpactFeedbackGenerator(style: .light)
    private let notify = UINotificationFeedbackGenerator()

    func tap(enabled: Bool) { if enabled { light.impactOccurred() } }
    func success(enabled: Bool) { if enabled { notify.notificationOccurred(.success) } }
    func warning(enabled: Bool) { if enabled { notify.notificationOccurred(.warning) } }
}

// MARK: Brand

/// The Oxyde mark (the X in a ring) from oxyde.ro, tinted with the app's colors.
struct OxydeMark: View {
    var size: CGFloat = 64
    var glow = true
    var body: some View {
        Image("OxydeLogoMark")
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .foregroundStyle(OX.gradient)
            .frame(width: size, height: size)
            .shadow(color: OX.brand.opacity(glow ? 0.6 : 0), radius: size * 0.18)
            .accessibilityHidden(true)
    }
}

struct OxydeWordmark: View {
    var size: CGFloat = 28
    var body: some View {
        HStack(alignment: .center, spacing: size * 0.35) {
            Image("OxydeLogoFull")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(height: size * 1.25)
                .foregroundStyle(OX.text)
            Text("MAP")
                .font(.system(size: size * 0.8, weight: .semibold))
                .tracking(size * 0.28)
                .foregroundStyle(OX.gradient)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Oxyde Map")
    }
}

/// Title text with the site's tight tracking.
struct OxTitle: View {
    let text: String
    var size: CGFloat = 28
    var body: some View {
        Text(text).font(.system(size: size, weight: .bold)).tracking(-0.02 * size)
    }
}

// MARK: Formatting helpers

extension AppSettings {
    var resolvedUnits: UnitSystem { units.resolved(regionCode: Locale.current.region?.identifier) }
}

extension Date {
    var shortTime: String { formatted(date: .omitted, time: .shortened) }
}
