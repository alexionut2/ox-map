import SwiftUI
import OxydeCore

/// A burst of confetti, drawn with Canvas so it costs almost nothing.
struct ConfettiView: View {
    var colors: [Color] = [OX.brand, OX.lavender, OX.ok, OX.warning, OX.error, .white]
    var duration: Double = 2.6

    private struct Piece {
        let x: Double, vx: Double, vy: Double, spin: Double, size: Double, color: Int, delay: Double
    }

    @State private var start = Date()
    @State private var pieces: [Piece] = (0..<90).map { _ in
        Piece(x: .random(in: 0.2...0.8), vx: .random(in: -0.45...0.45), vy: .random(in: -1.25 ... -0.6),
              spin: .random(in: -8...8), size: .random(in: 5...10), color: .random(in: 0..<6), delay: .random(in: 0...0.25))
    }

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { ctx, size in
                let t = timeline.date.timeIntervalSince(start)
                for p in pieces {
                    let lt = max(0, t - p.delay)
                    guard lt > 0, lt < duration else { continue }
                    let x = (p.x + p.vx * lt) * size.width
                    let y = size.height * 0.55 + (p.vy * lt + 0.9 * lt * lt) * size.height * 0.6
                    let fade = lt > duration - 0.6 ? (duration - lt) / 0.6 : 1
                    var c = ctx
                    c.opacity = fade
                    c.translateBy(x: x, y: y)
                    c.rotate(by: .radians(p.spin * lt))
                    let rect = CGRect(x: -p.size / 2, y: -p.size / 4, width: p.size, height: p.size / 2)
                    c.fill(Path(roundedRect: rect, cornerRadius: 1.5), with: .color(colors[p.color % colors.count]))
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Toast plus confetti when the driver levels up, unlocks a badge or arrives.
struct CelebrationOverlay: View {
    @Environment(AppModel.self) private var model
    @Environment(NavigationSession.self) private var nav
    @State private var shown: PlayStore.Celebration?

    var body: some View {
        ZStack(alignment: .top) {
            if let c = shown {
                ConfettiView().ignoresSafeArea().id(c.id)
                HStack(spacing: 14) {
                    ZStack {
                        Circle().fill(OX.gradient).frame(width: 46, height: 46)
                        Image(systemName: c.symbol).font(.title3.bold()).foregroundStyle(.white)
                            .symbolEffect(.bounce, value: c.id)
                    }
                    .shadow(color: OX.brand.opacity(0.6), radius: 10)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(c.kind == .achievement ? "ACHIEVEMENT UNLOCKED" : (c.kind == .levelUp ? "LEVEL UP" : "ARRIVED"))
                            .font(.caption2.weight(.bold)).tracking(1.2).foregroundStyle(OX.lavender)
                        Text(c.title).font(.headline)
                        Text(c.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                    Spacer(minLength: 0)
                }
                .padding(14)
                .oxPanel(.solid)
                .padding(.horizontal, OX.gutter)
                .padding(.top, 70)
                .transition(.move(edge: .top).combined(with: .scale(scale: 0.9)).combined(with: .opacity))
                .onTapGesture { withAnimation { shown = nil } }
            }
        }
        .allowsHitTesting(shown != nil)
        .onChange(of: model.play.celebration) { _, _ in present() }
        .onChange(of: nav.phase) { _, _ in present() }
    }

    private func present() {
        // Never pull the driver's eyes during turn-by-turn guidance: the toast waits
        // until the trip ends.
        guard let c = model.play.celebration, nav.phase != .navigating, shown?.id != c.id else { return }
        do {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) { shown = c }
            model.haptics.success(enabled: model.settings.value.hapticsEnabled)
            Task {
                try? await Task.sleep(nanoseconds: 3_500_000_000)
                if shown?.id == c.id { withAnimation(.easeInOut(duration: 0.4)) { shown = nil } }
                if model.play.celebration?.id == c.id { model.play.celebration = nil }
            }
        }
    }
}

/// Launch animation: the Oxyde mark draws in, the wordmark fades up, then the map shows.
struct SplashView: View {
    var onFinish: () -> Void
    @State private var ring: CGFloat = 0
    @State private var markScale: CGFloat = 0.6
    @State private var markOpacity: Double = 0
    @State private var wordOpacity: Double = 0
    @State private var glow = false

    var body: some View {
        ZStack {
            OX.ink.ignoresSafeArea()
            RadialGradient(colors: [OX.brand.opacity(glow ? 0.35 : 0), .clear], center: .center, startRadius: 10, endRadius: 320)
                .ignoresSafeArea()
            VStack(spacing: 26) {
                ZStack {
                    Circle()
                        .trim(from: 0, to: ring)
                        .stroke(OX.gradient, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .frame(width: 150, height: 150)
                    OxydeMark(size: 96)
                        .scaleEffect(markScale)
                        .opacity(markOpacity)
                }
                OxydeWordmark(size: 26).opacity(wordOpacity).offset(y: wordOpacity == 1 ? 0 : 10)
            }
        }
        .task {
            withAnimation(.easeInOut(duration: 0.8)) { ring = 1 }
            withAnimation(.spring(response: 0.6, dampingFraction: 0.6).delay(0.15)) { markScale = 1; markOpacity = 1 }
            withAnimation(.easeOut(duration: 0.5).delay(0.45)) { wordOpacity = 1 }
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) { glow = true }
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            onFinish()
        }
    }
}
