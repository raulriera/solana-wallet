import SwiftUI

/// The payment keypad: digits, the locale's decimal separator, and delete, laid out like the Phone keypad.
///
/// The keys type into the payment that the screen's ``KeypadPressAction`` names.
struct Keypad: View {
    /// The keys, row by row.
    private static let rows: [[KeypadKey]] = [
        [.digit(1), .digit(2), .digit(3)],
        [.digit(4), .digit(5), .digit(6)],
        [.digit(7), .digit(8), .digit(9)],
        [.decimalSeparator, .digit(0), .delete],
    ]

    var body: some View {
        // The keys share one glass sampling region, so they look alike wherever they sit.
        GlassEffectContainer(spacing: 16) {
            Grid(horizontalSpacing: 28, verticalSpacing: 16) {
                ForEach(Self.rows, id: \.self) { keys in
                    KeypadRow(keys: keys)
                }
            }
        }
        // Three columns by four rows of round keys, so rows hug the keys instead of spreading apart.
        .aspectRatio(0.8, contentMode: .fit)
    }
}
