import Foundation
import SwiftUI

/// Shows a token's total value in its quote currency; new values roll into place.
///
/// Abbreviated values shorten from 10,000 up, as in US$10.2K, while VoiceOver still reads the full value.
struct TokenValue: View {
    let total: Decimal
    let currency: String
    /// Whether values from 10,000 up are shortened, as on cards and rows.
    var abbreviates = false

    var body: some View {
        Text(total, format: abbreviates ? .abbreviatedValue(code: currency) : .value(code: currency))
            .contentTransition(.numericText(value: NSDecimalNumber(decimal: total).doubleValue))
            .accessibilityLabel(Text(total, format: .value(code: currency)))
    }
}

#Preview {
    VStack(alignment: .trailing) {
        TokenValue(total: 2_075, currency: "USD")
        TokenValue(total: 1_234_567.89, currency: "USD", abbreviates: true)
    }
}
