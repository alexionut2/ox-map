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

/// Fixed brand colors. Map and accent colors come from the active theme.
enum OX {
    static let black = Color(hex: "#050607")
    static let graphite = Color(hex: "#111317")
    static let graphiteRaised = Color(hex: "#1A1D22")
    static let metal = Color(hex: "#8C939D")
    static let hairline = Color.white.opacity(0.08)

    /// Accent presets offered in Settings.
    static let accents: [(name: String, hex: HexColor)] = [
        ("Electric Blue", "#2F7BFF"), ("Cyan", "#00E0FF"), ("Purple", "#8A5CFF"), ("Red", "#FF2D3D"),
        ("Lime", "#B6FF00"), ("Orange", "#FF7A00"), ("White", "#F4F6F8"),
    ]

    static let corner: CGFloat = 22
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
                    .fill(style == .glass ? AnyShapeStyle(.ultraThinMaterial) : AnyShapeStyle(OX.graphite.opacity(0.96)))
                    .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).strokeBorder(OX.hairline))
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
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(.tint, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .foregroundStyle(.black)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(duration: 0.2), value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
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

/// The Oxyde navigation mark: a faceted arrowhead inside a ring.
struct OxydeMark: View {
    var size: CGFloat = 64
    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(LinearGradient(colors: [.white.opacity(0.9), OX.metal.opacity(0.4)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: size * 0.06)
            ArrowheadShape()
                .fill(.tint)
                .frame(width: size * 0.46, height: size * 0.56)
                .shadow(color: Color.accentColor.opacity(0.6), radius: size * 0.12)
            ArrowheadShape()
                .fill(.black.opacity(0.28))
                .frame(width: size * 0.46, height: size * 0.56)
                .mask(Rectangle().frame(width: size * 0.23).offset(x: size * 0.115))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

struct ArrowheadShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.midX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.midX, y: r.maxY - r.height * 0.28))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        p.closeSubpath()
        return p
    }
}

struct OxydeWordmark: View {
    var size: CGFloat = 28
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: size * 0.35) {
            Text("OXYDE").font(.system(size: size, weight: .heavy)).tracking(size * 0.32)
            Text("MAP").font(.system(size: size, weight: .light)).tracking(size * 0.32).foregroundStyle(.tint)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Oxyde Map")
    }
}

// MARK: Formatting helpers

extension AppSettings {
    var resolvedUnits: UnitSystem { units.resolved(regionCode: Locale.current.region?.identifier) }
}

extension Date {
    var shortTime: String { formatted(date: .omitted, time: .shortened) }
}
