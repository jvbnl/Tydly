import SwiftUI
import TydlyCore

/// A decision waits. Amber badge in the header; confidence is a bar, the reason is one tap
/// away, parked items self-mute. "Nothing moves without you" anchors the foot.
struct DecisionView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        PersonaHeaderRow(name: model.personaName) {
            if case .needsDecision(let count) = model.agentState {
                TydlyBadge(text: L.decisionBadge(count), style: .warn)
            }
        }

        MenuSeparator()

        if let decision = model.decisions.first {
            DecisionCard(decision: decision)
        }

        ParkedRow()

        MenuSeparator()
        FooterNote(text: L.decisionFooter)
    }
}

/// The white overlay card: avatar, title, confidence + why, then Show me / Skip.
private struct DecisionCard: View {
    @EnvironmentObject private var model: AppModel
    let decision: Decision
    @State private var showReason = false

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .top, spacing: 8) {
                ProjectAvatar(project: decision.project)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L.decisionTitle(decision))
                        .font(Typography.cardTitle)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 6) {
                        ConfidenceBar(value: decision.confidence)
                        PillButton(L.why, style: .link, size: .small) {
                            withAnimation(.easeOut(duration: 0.15)) { showReason.toggle() }
                        }
                    }
                }
                Spacer(minLength: 0)
            }

            // Reasons on demand (Voice): one line, revealed by "why?".
            if showReason {
                Text(decision.reason)
                    .font(Typography.meta)
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 6) {
                // "Show me" opens the Finder demonstration (Phase 02). Until that lands it
                // stands in for the whole demonstrate → approve flow.
                PillButton(L.showMe, style: .primary, size: .small, fillWidth: true) {
                    model.approveTopDecision()
                }
                PillButton(L.skip, style: .outline, size: .small) {
                    model.skipTopDecision()
                }
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 8)
        .menuCard()
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
    }
}

/// "4 parked · asks again Fri ›" — skipped-twice items park and re-ask once (Rule 10).
private struct ParkedRow: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        MenuRow(interactive: true) {
            Image(systemName: "clock")
                .font(.system(size: 12))
                .foregroundStyle(Palette.textSecondary)
                .frame(width: 18)
            Text(L.parkedLine(count: model.parkedCount, day: model.parkedReAskLabel))
                .font(Typography.bodySmall)
                .foregroundStyle(Palette.textSecondaryStrong)
            Spacer(minLength: 8)
            Text("›").foregroundStyle(Palette.textSecondary.opacity(0.7))
        }
    }
}
