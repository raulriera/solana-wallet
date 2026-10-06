import Portfolio
import SwiftUI

/// A token's card as a button that selects the token and shows its details; the selected card lifts.
struct TokenCardOption<Card: View>: View {
    @Binding var selection: Holding.Identity?
    @Binding var preferredColumn: NavigationSplitViewColumn
    let id: Holding.Identity
    /// The card that the button shows.
    @ViewBuilder let card: Card

    var body: some View {
        let isSelected = selection == id

        Button {
            selection = id
            // A collapsed split view shows the details only when asked to.
            preferredColumn = .detail
        } label: {
            card
        }
        .buttonStyle(.tokenCard)
        .offset(y: isSelected ? -8 : 0)
        .animation(.snappy, value: isSelected)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
