import SwiftUI

/// The Apple page-control stepper: active dot is a 16×6 blue pill, inactive dots are
/// 6×6 at 15% black (README Phase 01).
struct PageControl: View {
    let count: Int
    let index: Int

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<count, id: \.self) { i in
                Capsule()
                    .fill(i == index ? Palette.primary : Color.black.opacity(0.15))
                    .frame(width: i == index ? 16 : 6, height: 6)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement()
        .accessibilityLabel(Text("Step \(index + 1) of \(count)"))
    }
}
