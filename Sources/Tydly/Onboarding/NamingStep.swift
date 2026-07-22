import SwiftUI
import TydlyCore

/// Step 3 — naming is ownership. Ten seconds of investment, skippable. Name chips, a color,
/// and a live preview of how the archivist signs its work. Skipping defaults to "Archivist".
struct NamingStep: View {
    @Binding var name: String
    @Binding var colorIndex: Int
    var onMeet: () -> Void
    var onSkip: () -> Void

    @State private var editingCustom = false
    @State private var customName = ""

    private let suggestions = Persona.nameSuggestions // Otto, Ada, Juno

    var body: some View {
        VStack(spacing: 8) {
            Text(L.onboarding_name_title)
                .font(Typography.onboardingTitle)
                .multilineTextAlignment(.center)

            // Name chips: a filled pill for the selection, a dashed "own…" for custom.
            HStack(spacing: 6) {
                ForEach(suggestions, id: \.self) { suggestion in
                    NameChip(text: suggestion, selected: !editingCustom && name == suggestion) {
                        editingCustom = false
                        name = suggestion
                    }
                }
                NameChip(text: L.onboarding_name_own, selected: editingCustom, dashed: true) {
                    editingCustom = true
                    name = customName.isEmpty ? "" : customName
                }
            }

            if editingCustom {
                TextField(L.onboarding_name_own, text: $customName)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
                    .onChange(of: customName) { newValue in
                        name = newValue
                    }
            }

            // Color swatches (deterministic project palette).
            HStack(spacing: 8) {
                ForEach(0..<Palette.avatar.count, id: \.self) { index in
                    ColorSwatch(color: Palette.avatarColor(index), selected: colorIndex == index) {
                        colorIndex = index
                    }
                }
            }
            .padding(.top, 2)

            // Preview: "Signs their work as [Name]" with the blue cursor tag.
            HStack(spacing: 8) {
                Text(L.onboarding_signs)
                    .font(Typography.onboardingSub)
                    .foregroundStyle(Palette.textSecondary)
                Spacer(minLength: 8)
                CursorTag(name: displayName)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.white.opacity(0.75))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(Color.black.opacity(0.07), lineWidth: 0.5)
            )

            Spacer(minLength: 6)

            HStack(spacing: 6) {
                PillButton(L.onboarding_meet(displayName), style: .primary, fillWidth: true, action: onMeet)
                PillButton(L.skip, style: .secondary, action: onSkip)
            }
        }
    }

    /// What the buttons and preview show: the chosen name, or the fallback if blank.
    private var displayName: String {
        name.isEmpty ? Persona.fallbackName : name
    }
}

private struct NameChip: View {
    let text: String
    let selected: Bool
    var dashed: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(text)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(selected ? (dashed ? Palette.primary : .white) : Palette.textSecondaryStrong)
                .padding(.horizontal, 8)
                .frame(height: 20)
                .background(chipBackground)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var chipBackground: some View {
        if dashed {
            Capsule().strokeBorder(
                Palette.textSecondary.opacity(0.5),
                style: StrokeStyle(lineWidth: 1, dash: [3, 2])
            )
        } else {
            Capsule().fill(selected ? Palette.primary : Palette.grayFill(0.13))
        }
    }
}

private struct ColorSwatch: View {
    let color: Color
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().fill(color).frame(width: 20, height: 20)
                if selected {
                    Circle().strokeBorder(Color.white, lineWidth: 2).frame(width: 20, height: 20)
                    Circle().strokeBorder(color, lineWidth: 1.5).frame(width: 24, height: 24)
                }
            }
            .frame(width: 24, height: 24)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Accent color"))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// The Figma-collaborator cursor tag: a blue pill showing the archivist's name.
private struct CursorTag: View {
    let name: String

    var body: some View {
        Text(name)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Capsule().fill(Palette.primary))
            .shadow(color: .black.opacity(0.25), radius: 1.5, x: 0, y: 1)
    }
}
