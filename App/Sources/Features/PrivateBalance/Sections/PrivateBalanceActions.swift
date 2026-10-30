import SwiftUI

/// Shows the private balance's actions as button rows.
struct PrivateBalanceActions: View {
    @Environment(\.palette) private var palette
    @Environment(\.moveBalance) private var moveBalance
    let canMakePublic: Bool

    var body: some View {
        Group {
            Button("Make SOL Private", systemImage: "eye.slash") { moveBalance?(.toPrivate) }
            if canMakePublic {
                Button("Make SOL Public", systemImage: "eye") { moveBalance?(.toPublic) }
            }
        }
        .foregroundStyle(palette.accent)
        .lineLimit(1)
    }
}
