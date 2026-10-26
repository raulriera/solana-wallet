import Foundation
import SwiftUI

/// A token's 24-hour price change: an up or down arrow and the size of the change.
///
/// The arrow carries the direction, so the label reads in any text color. New values roll into place.
struct DayChangeLabel: View {
    /// The change as a fraction, so `0.0129` reads as 1.29%.
    let change: Decimal

    var body: some View {
        let shown = shownChange
        HStack(spacing: 2) {
            Image(systemName: shown < 0 ? "arrow.down" : "arrow.up")
                .imageScale(.small)
                // An unchanged price keeps the arrow's space, so the percentage stays put when it moves again.
                .opacity(shown == 0 ? 0 : 1)
                .contentTransition(.symbolEffect(.replace))
            Text(abs(shown), format: .percent.precision(.fractionLength(2)))
                // The digits roll with the price, so a deeper drop rolls down even as the percentage grows.
                .contentTransition(.numericText(value: NSDecimalNumber(decimal: shown).doubleValue))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenChange)
    }

    /// The change rounded to the two percentage decimals the label shows, so a move too small to show
    /// reads as unchanged instead of pointing up or down at 0.00%.
    var shownChange: Decimal {
        var change = change
        var shown = Decimal()
        NSDecimalRound(&shown, &change, 4, .plain)
        return shown
    }

    /// The change as VoiceOver reads it, with the direction in words.
    private var spokenChange: LocalizedStringResource {
        let shown = shownChange
        let size = abs(shown)
        if shown > 0 { return "Up \(size, format: .percent.precision(.fractionLength(2))) over 24 hours" }
        if shown < 0 { return "Down \(size, format: .percent.precision(.fractionLength(2))) over 24 hours" }
        return "Unchanged over 24 hours"
    }
}

#Preview {
    VStack(alignment: .trailing) {
        DayChangeLabel(change: 0.0129)
        DayChangeLabel(change: -0.0347)
        DayChangeLabel(change: 0)
    }
}
