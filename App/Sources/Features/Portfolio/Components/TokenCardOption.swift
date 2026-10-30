import Portfolio
import SwiftUI

/// A token's card as a button that selects the token and shows its details.
struct TokenCardOption<Card: View>: View {
    @Binding var selection: Holding.Identity?
    @Binding var preferredColumn: NavigationSplitViewColumn
    let id: Holding.Identity
    @ViewBuilder let card: Card

    var body: some View {
        let isSelected = selection == id

        Button {
            selection = id
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
