import SwiftUI
import Transactions

/// Shows an address's first and last four characters in a fixed-width font.
struct ShortAddress: View {
    let address: Address

    var body: some View {
        Text(address, format: .shortAddress)
            .monospaced()
            .speechSpellsOutCharacters()
    }
}
