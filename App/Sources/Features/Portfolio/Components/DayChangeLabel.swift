import Foundation
import SwiftUI

/// A token's 24-hour price change: an up or down arrow and the size of the change.
struct DayChangeLabel: View {
    /// The change as a fraction, where `0.0129` is 1.29%.
    let change: Decimal

    var body: some View {
        let shown = shownChange
        HStack(spacing: 2) {
            Image(systemName: shown < 0 ? "arrow.down" : "arrow.up")
                .imageScale(.small)
                .opacity(shown == 0 ? 0 : 1)
                .contentTransition(.symbolEffect(.replace))
            Text(abs(shown), format: .percent.precision(.fractionLength(2)))
                .contentTransition(.numericText(value: shown))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenChange)
    }

    /// The change rounded to two decimal places of a percent.
    var shownChange: Decimal { change.rounded(scale: 4, .plain) }

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
