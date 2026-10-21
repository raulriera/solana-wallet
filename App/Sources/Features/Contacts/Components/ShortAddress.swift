import SwiftUI
import Transactions

/// Shows an address's first and last four characters in a fixed-width font, so people can match it at a glance;
/// VoiceOver spells them out.
///
/// Use it only where people can't copy the address: the shortened text is all a copy would take. Where they can,
/// show the whole address with middle truncation, as token details does for an account's owner.
struct ShortAddress: View {
    let address: Address

    var body: some View {
        Text(address, format: .shortAddress)
            .monospaced()
            .speechSpellsOutCharacters()
    }
}
