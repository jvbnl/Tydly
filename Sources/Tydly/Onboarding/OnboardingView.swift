import SwiftUI
import TydlyCore

/// The onboarding card (Phase 01): one floating glass card, three steps, one idea each.
/// Trust is set before anything runs — what it sees, where it works, who it is. Presented
/// in a transparent floating window by `AppDelegate`; the card supplies its own material,
/// radius, and shadow.
struct OnboardingView: View {
    var onFinish: () -> Void

    @EnvironmentObject private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var step = 0
    @State private var scope = FolderScope()          // Desktop + Downloads (fixed scope)
    @State private var name = Persona.suggestedName
    @State private var colorIndex = 0

    private let stepCount = 3

    var body: some View {
        VStack(spacing: 7) {
            PageControl(count: stepCount, index: step)

            Group {
                switch step {
                case 0:
                    PrivacyStep(onContinue: advance)
                case 1:
                    FolderScopeStep(scope: scope, onAllow: advance)
                default:
                    NamingStep(
                        name: $name,
                        colorIndex: $colorIndex,
                        onMeet: { finish(named: name.isEmpty ? Persona.fallbackName : name) },
                        onSkip: { finish(named: Persona.fallbackName) }
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .transition(.opacity)
            .id(step)
        }
        .padding(12)
        .frame(width: Metrics.onboardingCardWidth)
        .frame(minHeight: Metrics.onboardingCardMinHeight)
        .background(VisualEffectView(material: .popover))
        .clipShape(RoundedRectangle(cornerRadius: Radius.onboarding, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.onboarding, style: .continuous)
                .strokeBorder(Color.black.opacity(0.12), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.18), radius: 22, x: 0, y: 14)
        .padding(24) // transparent breathing room inside the clear window (shadow shows here)
    }

    private func advance() {
        if reduceMotion {
            step += 1
        } else {
            withAnimation(.easeOut(duration: 0.2)) { step += 1 }
        }
    }

    private func finish(named finalName: String) {
        let persona = Persona(name: finalName, colorIndex: colorIndex)
        model.completeOnboarding(persona: persona, scope: scope)
        onFinish()
    }
}
