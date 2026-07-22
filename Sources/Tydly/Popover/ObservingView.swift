import SwiftUI
import TydlyCore

/// The first-run observing pass (Phase 02): the blue dot pulses, and the copy says exactly
/// what's happening — reading, changing nothing. Files are untouched until a plan is
/// approved.
struct ObservingView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        StatusHeaderRow(color: Palette.primary, title: L.observingTitle)
        MenuRow {
            Text(L.observingScope(model.folderScope))
                .font(Typography.meta)
                .foregroundStyle(Palette.textSecondary)
            Spacer(minLength: 0)
        }
    }
}
