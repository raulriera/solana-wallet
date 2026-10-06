import SwiftUI

/// The pocket that the cards tuck into. It has the page's color, so only its cutout shows, over the cards.
struct CardPocket: View {
    @Environment(\.palette) private var palette

    var body: some View {
        PocketCutout()
            .fill(palette.surface)
            .frame(height: 120)
            .accessibilityHidden(true)
    }
}

#Preview {
    CardPocket()
}
