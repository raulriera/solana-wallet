import SwiftUI

/// The rows under the private balance while private balances are on: accent button rows, each led by its symbol, for
/// what the private balance can do. Make SOL Public shows only while some SOL is available.
struct PrivateBalanceActions: View {
    @Environment(\.palette) private var palette
    @Environment(\.moveBalance) private var moveBalance
    /// Whether some private SOL is available to make public.
    let canMakePublic: Bool

    var body: some View {
        Group {
            // The symbol matches the private-balance sign on SOL's card.
            Button("Make SOL Private", systemImage: "eye.slash") { moveBalance?(.toPrivate) }
            // Only available SOL can be made public; pending SOL waits until the network reports it.
            if canMakePublic {
                Button("Make SOL Public", systemImage: "eye") { moveBalance?(.toPublic) }
            }
        }
        .foregroundStyle(palette.accent)
        // Action rows stay one line at every text size; VoiceOver still reads the whole title.
        .lineLimit(1)
    }
}
