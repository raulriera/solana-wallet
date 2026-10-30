import SwiftUI

/// A row of the payment keypad.
struct KeypadRow: View {
    @Environment(\.locale) private var locale
    @Environment(\.pressKey) private var pressKey
    let keys: [KeypadKey]

    var body: some View {
        GridRow {
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

    /// Types a key with animation.
    ///
    /// - Parameter key: The pressed key.
    private func press(_ key: KeypadKey) {
        withAnimation(.snappy) { pressKey?(key) }
    }
}
