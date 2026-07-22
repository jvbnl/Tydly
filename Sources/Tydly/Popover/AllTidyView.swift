import SwiftUI
import TydlyCore

/// The calm default: master switch in the header, then Today's receipts, then Settings.
/// The log speaks in verbs + folder chips (Rule/Voice: "Filed 3 screenshots → Atlas ↩").
struct AllTidyView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        PersonaHeaderRow(name: model.personaName) {
            HStack(spacing: 8) {
                Text(L.allTidy)
                    .font(Typography.meta)
                    .foregroundStyle(Palette.textSecondary)
                Toggle("", isOn: $model.isEnabled)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .scaleEffect(0.85)
                    .accessibilityLabel(Text("\(model.personaName) enabled"))
            }
        }

        MenuSeparator()
        SectionLabel(L.today)
        ForEach(model.todayLog) { entry in
            LogRow(entry: entry)
        }

        MenuSeparator()
        SettingsRow()
    }
}

/// One receipt: green check + verb-count-noun + destination chip + undo glyph.
private struct LogRow: View {
    @EnvironmentObject private var model: AppModel
    let entry: ActionLogEntry

    var body: some View {
        MenuRow(interactive: true) {
            Image(systemName: "checkmark")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Palette.success)
            Text(L.filedLine(count: entry.count, kind: entry.kind))
                .font(Typography.menuRow)
                .strikethrough(entry.undone, color: Palette.textSecondary)
            Spacer(minLength: 8)
            FolderChip(name: entry.destination.name)
            if !entry.undone {
                Button {
                    model.undo(entry)
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.primary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Undo"))
            }
        }
        .opacity(entry.undone ? 0.5 : 1)
    }
}

/// Opens Settings (Phase 07). Present now for layout truth; wired when that pane lands.
private struct SettingsRow: View {
    var body: some View {
        Button {
            // TODO(Phase 07): open the Settings window. ⌘, will bind here too.
        } label: {
            MenuRow(interactive: true) {
                Text(L.settings)
                    .font(Typography.menuRow)
                    .foregroundStyle(Palette.text.opacity(0.9))
                Spacer(minLength: 8)
                Text("⌘,")
                    .font(Typography.meta)
                    .foregroundStyle(Palette.textSecondary.opacity(0.7))
            }
        }
        .buttonStyle(.plain)
    }
}
