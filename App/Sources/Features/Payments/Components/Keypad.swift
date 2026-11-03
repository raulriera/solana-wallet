import SwiftUI

/// The payment keypad of digits, the locale's decimal separator, and delete.
struct Keypad: View {
    @State private var rowGap: CGFloat = 0

    nonisolated private static let keys: [KeypadKey] = [
        .digit(1), .digit(2), .digit(3),
        .digit(4), .digit(5), .digit(6),
        .digit(7), .digit(8), .digit(9),
        .decimalSeparator, .digit(0), .delete,
    ]

    var body: some View {
        GlassEffectContainer(spacing: rowGap) {
            KeypadLayout {
                ForEach(Self.keys, id: \.self) { key in
                    KeypadKeyButton(key: key)
                }
            }
        }
        .onGeometryChange(for: CGFloat.self) { proxy in
            KeypadLayout.rowGap(inKeypadOf: proxy.size, count: Self.keys.count)
        } action: { rowGap in
            self.rowGap = rowGap
        }
    }
}
