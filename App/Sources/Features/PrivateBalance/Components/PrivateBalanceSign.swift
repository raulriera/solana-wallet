import SwiftUI

/// Shows beside SOL's balance in the token list that the account also holds private SOL, without its amount.
///
/// It takes the balance's font and the caller's secondary style. VoiceOver reads it after the balance.
struct PrivateBalanceSign: View {
    var body: some View {
        Image(systemName: "eye.slash")
            .accessibilityLabel(Text("and a private balance",
                                     comment: "VoiceOver, after SOL's balance in the token list, when the account also holds private SOL."))
            // The sign shows before the balance, but VoiceOver reads it after the balance.
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
