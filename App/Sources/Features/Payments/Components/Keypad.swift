import SwiftUI

/// The payment keypad of digits, the locale's decimal separator, and delete.
struct Keypad: View {
    private static let rows: [[KeypadKey]] = [
        [.digit(1), .digit(2), .digit(3)],
        [.digit(4), .digit(5), .digit(6)],
        [.digit(7), .digit(8), .digit(9)],
        [.decimalSeparator, .digit(0), .delete],
    ]

    var body: some View {
        GlassEffectContainer(spacing: 16) {
            Grid(horizontalSpacing: 28, verticalSpacing: 16) {
                ForEach(Self.rows, id: \.self) { keys in
                    KeypadRow(keys: keys)
                }
            }
        }
        .aspectRatio(0.8, contentMode: .fit)
    }
}
