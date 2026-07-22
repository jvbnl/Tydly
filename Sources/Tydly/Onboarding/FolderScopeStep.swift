import SwiftUI
import TydlyCore

/// Step 2 — least privilege, stated in the button itself. The two folders Otto may watch;
/// the rest of the Mac stays off-limits. Scope is fixed (Desktop + Downloads), so the
/// button copy stays exact (CLAUDE.md: do not change).
struct FolderScopeStep: View {
    let scope: FolderScope
    var onAllow: () -> Void

    var body: some View {
        VStack(spacing: 7) {
            Text(L.onboarding_scope_title)
                .font(Typography.onboardingTitle)
                .multilineTextAlignment(.center)

            FolderRow(icon: "display", name: L.onboarding_desktop)
            FolderRow(icon: "arrow.down.circle", name: L.onboarding_downloads)

            Text(L.onboarding_scope_sub)
                .font(Typography.onboardingSub)
                .foregroundStyle(Palette.textSecondary)
                .multilineTextAlignment(.center)

            Spacer(minLength: 8)

            PillButton(L.onboarding_allow, style: .primary, fillWidth: true, action: onAllow)
        }
    }
}

private struct FolderRow: View {
    let icon: String
    let name: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .regular))
                .frame(width: 18)
            Text(name).font(.system(size: 13, weight: .medium))
            Spacer(minLength: 8)
            Image(systemName: "checkmark")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Palette.primary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.white.opacity(0.9))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(Color.black.opacity(0.08), lineWidth: 0.5)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(name), allowed"))
    }
}
