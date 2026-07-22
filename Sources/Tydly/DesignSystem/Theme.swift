import SwiftUI
import AppKit

// The single source of truth for tokens — colors, type, radii, spacing, materials —
// mapping DESIGN.md to SwiftUI/AppKit. When in doubt, do what the Wi-Fi menu does.

// MARK: - Color tokens

enum Palette {
    // Semantic accents. These are the light-mode values from DESIGN.md; blue/green/amber/
    // red match the system accents closely enough to read correctly in dark mode too.
    // Color semantics are exclusive: green = tidy, blue = working, amber = waiting-on-user,
    // grey = paused, red = broken. Never use red for a busy state (Rule 5).
    static let primary = Color(hex: 0x007AFF)   // buttons, selection, links, working
    static let success = Color(hex: 0x34C759)   // tidy dot, done badge, high-confidence bar
    static let warning = Color(hex: 0xFF9F0A)   // needs-you, demotion, low-confidence bar
    static let danger  = Color(hex: 0xFF3B30)   // broken / error ONLY

    // Text. Prefer `.primary` / `.secondary` where possible so dark mode adapts; these are
    // the literal light-mode equivalents for pixel matching against the mock.
    static let text = Color(hex: 0x1D1D1F)
    static let textSecondary = Color(nsColor: NSColor(srgbRed: 60/255, green: 60/255, blue: 67/255, alpha: 0.60))
    /// .75 opacity variant for small sizes (AA contrast — DESIGN.md).
    static let textSecondaryStrong = Color(nsColor: NSColor(srgbRed: 60/255, green: 60/255, blue: 67/255, alpha: 0.75))
    static let separator = Color(nsColor: NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.10))

    // Deep blue used for the "auto" badge text.
    static let primaryDeep = Color(hex: 0x0A63C9)
    static let dangerText = Color(hex: 0xD70015)
    static let successText = Color(hex: 0x1D7A3A)
    static let warningText = Color(hex: 0xB36B00)

    // Deterministic per-project avatar palette (index from `AvatarPalette`).
    static let avatar: [Color] = [
        Color(hex: 0x3478F6),
        Color(hex: 0x2F9E8F),
        Color(hex: 0x8E6BD0),
        Color(hex: 0xC77D4A)
    ]

    static func avatarColor(_ index: Int) -> Color {
        avatar[((index % avatar.count) + avatar.count) % avatar.count]
    }
}

// MARK: - Typography (SF only; no other families)

enum Typography {
    static let menuTitle     = Font.system(size: 13, weight: .semibold)   // "Otto", state lines
    static let menuRow       = Font.system(size: 13, weight: .regular)    // menu items
    static let cardTitle     = Font.system(size: 12.5, weight: .semibold) // decision titles, rule names
    static let bodySmall     = Font.system(size: 12, weight: .regular)    // supporting copy
    static let meta          = Font.system(size: 11, weight: .regular)    // timestamps, hints, footers
    static let sectionLabel  = Font.system(size: 11, weight: .semibold)   // "Today", "Needs you"
    static let statNumber    = Font.system(size: 20, weight: .bold)       // werkbriefje grid
    static let onboardingTitle = Font.system(size: 15, weight: .semibold)
    static let onboardingSub = Font.system(size: 11.5, weight: .regular)
    static let badge         = Font.system(size: 10, weight: .semibold)
    static let chip          = Font.system(size: 10.5, weight: .medium)
}

// MARK: - Metrics

enum Radius {
    static let menu: CGFloat = 11
    static let window: CGFloat = 12
    static let card: CGFloat = 9
    static let onboarding: CGFloat = 14
    static let button: CGFloat = 7
    static let buttonSmall: CGFloat = 6
    static let pill: CGFloat = 999
    static let chip: CGFloat = 5
}

enum Metrics {
    static let popoverWidth: CGFloat = 290
    static let onboardingCardWidth: CGFloat = 250
    static let onboardingCardMinHeight: CGFloat = 196
}

// MARK: - Color hex init

extension Color {
    /// 0xRRGGBB in sRGB.
    init(hex: UInt32, alpha: Double = 1) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8) & 0xFF) / 255
        let b = Double(hex & 0xFF) / 255
        self = Color(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }
}

// MARK: - Materials

/// An NSVisualEffectView bridged into SwiftUI — the real macOS menu/popover material,
/// so surfaces are correct in both light and dark mode (DESIGN.md: derive dark from
/// system materials, do not hand-pick).
struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .menu
    var blending: NSVisualEffectView.BlendingMode = .behindWindow
    var emphasized: Bool = false

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blending
        view.state = .active
        view.isEmphasized = emphasized
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.blendingMode = blending
        view.isEmphasized = emphasized
    }
}

extension View {
    /// The popover/menu surface: menu material + hairline ring + soft shadow. The ring
    /// and shadow together are the literal macOS menu material (DESIGN.md).
    func menuSurface(cornerRadius: CGFloat = Radius.menu) -> some View {
        self
            .background(VisualEffectView(material: .menu, blending: .behindWindow))
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.black.opacity(0.12), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.18), radius: 17, x: 0, y: 10)
    }

    /// A grouped card inside a menu: translucent white fill + hairline ring (DESIGN.md).
    func menuCard() -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .fill(Color.white.opacity(0.75))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .strokeBorder(Color.black.opacity(0.07), lineWidth: 0.5)
            )
    }
}
