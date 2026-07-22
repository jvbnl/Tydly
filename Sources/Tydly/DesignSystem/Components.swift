import SwiftUI
import TydlyCore

// shadcn component anatomy, Apple skin. Every measurement here traces to a class in
// `Archivaris Journey.dc.html` (.sbtn, .sbdg, .fch, .sprog, .hav, .hdot, …).

extension Palette {
    /// The neutral system fill used for secondary buttons (.14), badges/chips (.13),
    /// and progress tracks (.16) — rgba(120,120,128, a).
    static func grayFill(_ opacity: Double) -> Color {
        Color(nsColor: NSColor(srgbRed: 120/255, green: 120/255, blue: 128/255, alpha: opacity))
    }
}

// MARK: - Button (.sbtn)

/// The primary control. Variants and sizes map 1:1 to DESIGN.md §Components → Button.
struct PillButton: View {
    enum Style { case primary, secondary, outline, link, destructive }
    enum Size { case regular, small }

    let title: String
    var style: Style = .primary
    var size: Size = .regular
    var fillWidth: Bool = false
    var systemImage: String? = nil
    let action: () -> Void

    init(
        _ title: String,
        style: Style = .primary,
        size: Size = .regular,
        fillWidth: Bool = false,
        systemImage: String? = nil,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.style = style
        self.size = size
        self.fillWidth = fillWidth
        self.systemImage = systemImage
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            if style == .link {
                linkLabel
            } else {
                pillLabel
            }
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }

    private var linkLabel: some View {
        content
            .font(.system(size: size == .regular ? 12 : 11, weight: .medium))
            .foregroundStyle(Palette.primary)
            .padding(.horizontal, 4)
    }

    private var pillLabel: some View {
        content
            .font(.system(size: size == .regular ? 12 : 11, weight: .medium))
            .frame(maxWidth: fillWidth ? .infinity : nil)
            .frame(height: size == .regular ? 26 : 22)
            .padding(.horizontal, size == .regular ? 11 : 8)
            .foregroundStyle(foreground)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(ring)
            .shadow(color: shadowColor, radius: shadowRadius, x: 0, y: shadowY)
    }

    private var content: some View {
        HStack(spacing: 6) {
            if let systemImage { Image(systemName: systemImage) }
            Text(title)
        }
    }

    private var cornerRadius: CGFloat { size == .regular ? Radius.button : Radius.buttonSmall }

    private var foreground: Color {
        switch style {
        case .primary:     return .white
        case .secondary:   return Palette.text
        case .outline:     return Palette.text
        case .link:        return Palette.primary
        case .destructive: return Palette.dangerText
        }
    }

    @ViewBuilder private var background: some View {
        switch style {
        case .primary:     Palette.primary
        case .secondary:   Palette.grayFill(0.14)
        case .outline:     Color.white
        case .link:        Color.clear
        case .destructive: Palette.danger.opacity(0.10)
        }
    }

    @ViewBuilder private var ring: some View {
        if style == .outline {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Color.black.opacity(0.12), lineWidth: 0.5)
        }
    }

    // Only the primary button carries a soft accent shadow (0 1 2 rgba(0,122,255,.3)).
    private var shadowColor: Color { style == .primary ? Palette.primary.opacity(0.3) : .clear }
    private var shadowRadius: CGFloat { style == .primary ? 1.5 : 0 }
    private var shadowY: CGFloat { style == .primary ? 1 : 0 }
}

// MARK: - Badge (.sbdg)

struct TydlyBadge: View {
    enum Style { case neutral, ok, warn, outline }
    let text: String
    var style: Style = .neutral

    var body: some View {
        Text(text)
            .font(Typography.badge)
            .foregroundStyle(foreground)
            .padding(.horizontal, 7)
            .frame(height: 17)
            .background(background)
            .clipShape(Capsule())
            .overlay {
                if style == .outline {
                    Capsule().strokeBorder(Color.black.opacity(0.15), lineWidth: 0.5)
                }
            }
    }

    private var foreground: Color {
        switch style {
        case .neutral: return Palette.textSecondaryStrong
        case .ok:      return Palette.successText
        case .warn:    return Palette.warningText
        case .outline: return Palette.textSecondaryStrong
        }
    }

    @ViewBuilder private var background: some View {
        switch style {
        case .neutral: Palette.grayFill(0.13)
        case .ok:      Palette.success.opacity(0.15)
        case .warn:    Palette.warning.opacity(0.17)
        case .outline: Color.clear
        }
    }
}

// MARK: - Folder chip (.fch)

/// The key log pattern: folder glyph + name in a grey pill. Every receipt ends with one.
struct FolderChip: View {
    let name: String
    var onDark: Bool = false

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "folder")
                .font(.system(size: 9, weight: .medium))
            Text(name)
        }
        .font(Typography.chip)
        .foregroundStyle(onDark ? Color.white : Palette.text)
        .padding(.horizontal, 6)
        .padding(.vertical, 1.5)
        .background(
            RoundedRectangle(cornerRadius: Radius.chip, style: .continuous)
                .fill(onDark ? Color.white.opacity(0.14) : Palette.grayFill(0.13))
        )
    }
}

// MARK: - Confidence bar (.sprog)

/// A bar, never a number (Voice rule). Green ≥ 85%, amber below.
struct ConfidenceBar: View {
    let value: Double            // 0…1
    var width: CGFloat = 50

    var body: some View {
        ZStack(alignment: .leading) {
            Capsule().fill(Palette.grayFill(0.16))
            Capsule()
                .fill(Rules.isConfidenceHigh(value) ? Palette.success : Palette.warning)
                .frame(width: max(0, min(1, value)) * width)
        }
        .frame(width: width, height: 4)
        .accessibilityElement()
        .accessibilityLabel("Confidence")
        .accessibilityValue(Rules.isConfidenceHigh(value) ? "high" : "low")
    }
}

// MARK: - Progress ring (goal gradient for rule promotion)

struct ProgressRing: View {
    let progress: Double        // 0…1
    let centerText: String
    var size: CGFloat = 32

    var body: some View {
        ZStack {
            Circle().stroke(Color.black.opacity(0.08), lineWidth: 3)
            Circle()
                .trim(from: 0, to: max(0, min(1, progress)))
                .stroke(Palette.primary, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(centerText).font(.system(size: 8.5, weight: .bold))
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Avatar (.hav)

struct ProjectAvatar: View {
    let color: Color
    let initial: String
    var size: CGFloat = 22
    var ringed: Bool = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .overlay(
                Text(initial)
                    .font(.system(size: size * 0.45, weight: .semibold))
                    .foregroundStyle(.white)
            )
            .overlay {
                if ringed {
                    Circle().strokeBorder(Color.white, lineWidth: 2)
                }
            }
    }
}

extension ProjectAvatar {
    init(project: Project, size: CGFloat = 22, ringed: Bool = false) {
        self.init(color: Palette.avatarColor(project.colorIndex), initial: project.initial, size: size, ringed: ringed)
    }
}

// MARK: - Status dot (.hdot) with optional pulse

/// The pulsing presence dot. The 1.6s soft-ring pulse runs only when `pulsing` is true
/// and Reduce Motion is off (Rule 8 / DESIGN.md motion).
struct StatusDot: View {
    let color: Color
    var size: CGFloat = 7
    var pulsing: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animate = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .overlay {
                if pulsing && !reduceMotion {
                    Circle()
                        .stroke(color.opacity(0.45), lineWidth: size * 0.5)
                        .scaleEffect(animate ? 2.4 : 1)
                        .opacity(animate ? 0 : 1)
                        .animation(.easeOut(duration: 1.6).repeatForever(autoreverses: false), value: animate)
                }
            }
            .onAppear { animate = true }
    }
}

// MARK: - Menu scaffolding

/// Section header inside the popover (.msec) — "Today", "Needs you".
struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(Typography.sectionLabel)
            .foregroundStyle(Palette.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.top, 4)
            .padding(.bottom, 2)
    }
}

/// The .5px inset menu separator (.msep).
struct MenuSeparator: View {
    var body: some View {
        Rectangle()
            .fill(Palette.separator)
            .frame(height: 0.5)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
    }
}

/// A menu row (.mrow): 8pt gap, 5×10 padding, 7pt corner, with a subtle hover highlight
/// when it is interactive.
struct MenuRow<Content: View>: View {
    var interactive: Bool = false
    var content: () -> Content
    @State private var hovering = false

    init(interactive: Bool = false, @ViewBuilder content: @escaping () -> Content) {
        self.interactive = interactive
        self.content = content
    }

    var body: some View {
        HStack(spacing: 8, content: content)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(interactive && hovering ? Color.primary.opacity(0.06) : Color.clear)
            )
            .contentShape(Rectangle())
            .onHover { if interactive { hovering = $0 } }
    }
}
