import SwiftUI
import TydlyCore

/// The menu-bar item: the template glyph plus one of five badge states (Phase 03).
/// The glyph tints with the menu bar; badges keep their semantic color.
///
///   quiet     → plain glyph, no animation (Rule 8)
///   working   → blue badge dot, 1.6s pulse
///   needs you → amber count badge
///   paused    → 40% opacity, no badge
///   broken    → red badge dot
struct MenuBarLabel: View {
    let state: IconState

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Image(nsImage: MenuGlyph.shared)
                .opacity(state == .paused ? 0.4 : 1)
            badge
        }
        .frame(width: 22, height: 16)
        .accessibilityLabel("Tydly")
        .accessibilityValue(accessibilityValue)
    }

    @ViewBuilder private var badge: some View {
        switch state {
        case .quiet, .paused:
            EmptyView()
        case .working:
            dotBadge(color: Palette.primary, pulsing: true)
        case .broken:
            dotBadge(color: Palette.danger, pulsing: false)
        case .needsYou(let count):
            countBadge(count)
        }
    }

    // Blue/red 6pt dot with a white separator ring; optional 1.6s pulse (working only,
    // and never under Reduce Motion).
    private func dotBadge(color: Color, pulsing: Bool) -> some View {
        ZStack {
            if pulsing && !reduceMotion {
                PulseRing(color: color, diameter: 6)
            }
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
                .overlay(Circle().strokeBorder(Color.white.opacity(0.9), lineWidth: 1.5))
        }
        .offset(x: 2, y: -1)
    }

    // Amber count pill (Rule 5: amber = waiting on user, never red for "busy").
    private func countBadge(_ count: Int) -> some View {
        Text("\(count)")
            .font(.system(size: 8.5, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 3)
            .frame(minWidth: 13, minHeight: 13)
            .background(Capsule().fill(Palette.warning))
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.9), lineWidth: 1))
            .offset(x: 5, y: -4)
    }

    private var accessibilityValue: String {
        switch state {
        case .quiet:                 return "All tidy"
        case .working:               return "Working"
        case .needsYou(let count):   return count == 1 ? "1 decision waiting" : "\(count) decisions waiting"
        case .paused:                return "Paused"
        case .broken:                return "Needs attention"
        }
    }
}

/// The 1.6s soft expanding ring behind a badge dot. Isolated so it can be reused and so
/// its animation is trivially gated by the caller (Reduce Motion / idle → not shown).
private struct PulseRing: View {
    let color: Color
    let diameter: CGFloat
    @State private var animate = false

    var body: some View {
        Circle()
            .stroke(color.opacity(0.45), lineWidth: 3)
            .frame(width: diameter, height: diameter)
            .scaleEffect(animate ? 2.6 : 1)
            .opacity(animate ? 0 : 1)
            .animation(.easeOut(duration: 1.6).repeatForever(autoreverses: false), value: animate)
            .onAppear { animate = true }
    }
}
