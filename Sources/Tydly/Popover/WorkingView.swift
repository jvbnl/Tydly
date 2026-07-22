import SwiftUI
import TydlyCore

/// Working, live. Figma-style presence: where Otto is, what he's touching, right now.
/// The blue dot pulses while analyzing; the footer promises the next sweep waits for idle.
struct WorkingView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        StatusHeaderRow(
            color: Palette.primary,
            title: L.sortingLine(count: model.workingQueue.count, location: model.workingLocation)
        )
        WorkingCard(items: model.workingQueue)
        MenuSeparator()
        FooterNote(text: L.workingFooter)
    }
}

private struct WorkingCard: View {
    let items: [WorkingItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(items) { item in
                HStack(spacing: 7) {
                    Circle()
                        .fill(item.status == .reading ? Palette.primary : Color.black.opacity(0.2))
                        .frame(width: 5, height: 5)
                    Text(item.filename)
                        .font(Typography.bodySmall)
                    Spacer(minLength: 8)
                    Text(item.status == .reading ? L.working_reading : L.working_queued)
                        .font(.system(size: 10.5))
                        .foregroundStyle(Palette.textSecondary)
                }
                .opacity(item.status == .reading ? 1 : 0.55)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 8)
        .menuCard()
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
    }
}
