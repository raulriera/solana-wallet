import SwiftUI

/// One row of the payment keypad.
struct KeypadRow: View {
    @Environment(\.locale) private var locale
    @Environment(\.pressKey) private var pressKey
    /// The row's keys, from leading to trailing.
    let keys: [KeypadKey]

    var body: some View {
        GridRow {
            // Each key appears once in its row and never changes, so it identifies itself.
            // swiftfairy:disable:next list-identity-costly-to-compare
            ForEach(keys, id: \.self) { key in
                switch key {
                case .digit(let digit):
                    Button {
                        press(key)
                    } label: {
                        Text(digit, format: .number)
                    }
                    .buttonStyle(.keypadKey)
                case .decimalSeparator:
                    Button {
                        press(key)
                    } label: {
                        Text(locale.decimalSeparator ?? ".")
                    }
                    .buttonStyle(.keypadSymbolKey)
                    .accessibilityLabel("Decimal Point")
                case .delete:
                    Button("Delete", systemImage: "delete.backward") {
                        press(key)
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.keypadSymbolKey)
                }
            }
        }
    }

    /// Types a key, rolling the amount's digits into place.
    /// - Parameter key: The pressed key.
    private func press(_ key: KeypadKey) {
        withAnimation(.snappy) { pressKey?(key) }
    }
}
