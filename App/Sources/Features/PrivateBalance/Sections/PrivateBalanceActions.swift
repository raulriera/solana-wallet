import Portfolio
import SwiftUI

/// Shows the private balance's actions as button rows.
struct PrivateBalanceActions: View {
    @Environment(\.palette) private var palette
    @Environment(\.moveBalance) private var moveBalance
    /// The spendable private balance.
    let available: Amount

    var body: some View {
        Group {
            Button("Make SOL Private", systemImage: "eye.slash") { moveBalance?(.toPrivate) }
            if available.units > 0 {
                Button("Make SOL Public", systemImage: "eye") { moveBalance?(.toPublic) }
            }
        }
        .foregroundStyle(palette.accent)
        .lineLimit(1)
    }
}
