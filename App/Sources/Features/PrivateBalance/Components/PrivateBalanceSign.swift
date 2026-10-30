import SwiftUI

/// Shows that the account also holds private SOL, without its amount.
struct PrivateBalanceSign: View {
    var body: some View {
        Image(systemName: "eye.slash")
            .accessibilityLabel(Text("and a private balance",
                                     comment: "VoiceOver, after SOL's balance in the token list, when the account also holds private SOL."))
            .accessibilitySortPriority(-1)
    }
}

#Preview {
    HStack {
        PrivateBalanceSign()
            .foregroundStyle(.secondary)
        Text("1.25 SOL")
    }
    .font(.headline)
}
