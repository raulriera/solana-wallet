import SwiftUI

/// The rows under the private balance while private balances are on: accent button rows, each led by its symbol, for
/// what the private balance can do.
struct PrivateBalanceActions: View {
    @Environment(\.palette) private var palette
    let model: PrivateBalanceModel
    /// The account's public SOL, in lamports, which a deposit can add.
    let publicLamports: UInt64

    var body: some View {
        // The symbol matches the private-balance sign on SOL's card.
        Button("Add to Private Balance", systemImage: "eye.slash") {
            model.addToPrivateBalance(publicLamports: publicLamports)
        }
        .foregroundStyle(palette.accent)
    }
}
