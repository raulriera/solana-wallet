import SwiftUI

/// The rows under the private balance while private balances are on: accent button rows, each led by its symbol, for
/// what the private balance can do. Make SOL Public shows only while some SOL is available.
struct PrivateBalanceActions: View {
    @Environment(\.palette) private var palette
    let model: PrivateBalanceModel
    /// The account's public SOL, in lamports, which a deposit can add.
    let publicLamports: UInt64

    var body: some View {
        Group {
            // The symbol matches the private-balance sign on SOL's card.
            Button("Make SOL Private", systemImage: "eye.slash") {
                model.addToPrivateBalance(publicLamports: publicLamports)
            }
            // Only available SOL can be made public; pending SOL waits until the network reports it.
            if model.availableLamports != nil {
                Button("Make SOL Public", systemImage: "eye", action: model.moveToPublicBalance)
            }
        }
        .foregroundStyle(palette.accent)
        // Action rows stay one line at every text size; VoiceOver still reads the whole title.
        .lineLimit(1)
    }
}
