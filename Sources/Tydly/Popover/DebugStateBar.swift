import SwiftUI
import TydlyCore

#if DEBUG
/// A developer-only strip at the foot of the popover for jumping between agent states and
/// replaying onboarding without a file engine or Xcode previews. Compiled out of release
/// builds — it never ships.
struct DebugStateBar: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        MenuSeparator()
        MenuRow {
            TydlyBadge(text: "DEBUG", style: .outline)
            Spacer(minLength: 6)
            ForEach(AppModel.PreviewState.allCases) { state in
                Button(state.label) { model.debugApply(state) }
                    .buttonStyle(.plain)
                    .font(.system(size: 10, weight: model.debugState == state ? .semibold : .regular))
                    .foregroundStyle(model.debugState == state ? Palette.primary : Palette.textSecondary)
            }
        }
        MenuRow {
            Button("Replay onboarding") {
                model.debugResetOnboarding()
                NotificationCenter.default.post(name: .tydlyShowOnboarding, object: nil)
            }
            .buttonStyle(.plain)
            .font(.system(size: 10))
            .foregroundStyle(Palette.primary)
            Spacer(minLength: 0)
        }
    }
}
#endif
