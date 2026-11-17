import SwiftUI
import Transactions

/// A token's card as a button that selects the token and shows its details.
struct TokenCardOption<Card: View>: View {
    @Binding var selection: Asset.ID?
    @Binding var preferredColumn: NavigationSplitViewColumn
    let id: Asset.ID
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
