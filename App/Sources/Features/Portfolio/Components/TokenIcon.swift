import SwiftUI

/// A token's round icon, showing the first letter of its symbol until artwork is available.
struct TokenIcon: View {
    @ScaledMetric(relativeTo: .headline) private var diameter = 40
    let symbol: String

    var body: some View {
        Text(symbol.prefix(1).uppercased())
            .font(.headline)
            .foregroundStyle(.secondary)
            .frame(width: diameter, height: diameter)
            .background(.fill.tertiary, in: .circle)
            .accessibilityHidden(true)
    }
}

#Preview {
    TokenIcon(symbol: "SOL")
}
