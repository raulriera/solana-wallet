import SwiftUI

/// A section that chooses how the portfolio lists its tokens.
struct TokenLayoutSection: View {
    @Binding var selection: CardStyle.Layout

    var body: some View {
        Section("Show Tokens As") {
            Button {
                selection = .cards
            } label: {
                Text("Cards", comment: "A choice in Settings > Appearance > Show Tokens As: the portfolio shows tokens as overlapping cards.")
            }
            .checked(selection == .cards)
            Button {
                selection = .rows
            } label: {
                Text("Rows", comment: "A choice in Settings > Appearance > Show Tokens As: the portfolio shows tokens as list rows.")
            }
            .checked(selection == .rows)
        }
    }
}
