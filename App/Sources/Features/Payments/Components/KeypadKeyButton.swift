import SwiftUI

/// A key of the payment keypad.
struct KeypadKeyButton: View {
    @Environment(\.locale) private var locale
    @Environment(\.pressKey) private var pressKey
    let key: KeypadKey

    var body: some View {
        switch key {
        case .digit(let digit):
            Button {
                press()
            } label: {
                Text(digit, format: .number)
            }
            .buttonStyle(.keypadKey)
        case .decimalSeparator:
            Button {
                press()
            } label: {
                Text(locale.decimalSeparator ?? ".")
            }
            .buttonStyle(.keypadSymbolKey)
            .accessibilityLabel("Decimal Point")
        case .delete:
            Button("Delete", systemImage: "delete.backward") {
                press()
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.keypadSymbolKey)
        }
    }

    /// Types the key with animation.
    private func press() {
        withAnimation(.snappy) { pressKey?(key) }
    }
}
