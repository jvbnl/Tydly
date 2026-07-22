import SwiftUI

/// Step 1 — the promise before the pitch. Green lock tile, one title, one sub, Continue.
struct PrivacyStep: View {
    var onContinue: () -> Void

    var body: some View {
        VStack(spacing: 7) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Palette.success.opacity(0.14))
                .frame(width: 40, height: 40)
                .overlay(
                    Image(systemName: "lock")
                        .font(.system(size: 18, weight: .regular))
                        .foregroundStyle(Palette.successText)
                )

            Text(L.onboarding_privacy_title)
                .font(Typography.onboardingTitle)
                .multilineTextAlignment(.center)

            Text(L.onboarding_privacy_sub)
                .font(Typography.onboardingSub)
                .foregroundStyle(Palette.textSecondary)
                .multilineTextAlignment(.center)

            Spacer(minLength: 8)

            PillButton(L.onboarding_continue, style: .primary, fillWidth: true, action: onContinue)
        }
    }
}
