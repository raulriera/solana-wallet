import SwiftUI

/// Shows that the account also holds the token privately, without its amount.
struct PrivateBalanceSign: View {
    var body: some View {
        Image(systemName: "shield")
            .accessibilityLabel(Text("and a private balance",
                                     comment: "VoiceOver, after a token's balance in the token list or card stack, when the account also holds that token privately."))
            .accessibilitySortPriority(-1)
    }
}

#Preview {
    HStack {
        PrivateBalanceSign()
            .fontWeight(.regular)
            .foregroundStyle(.secondary)
        Text("1.25 SOL")
    }
    .font(.headline)
}
