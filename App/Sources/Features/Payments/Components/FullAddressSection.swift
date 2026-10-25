import SwiftUI
import Transactions

/// A form section with a whole address, which people can copy with a touch and hold, under an Address header.
struct FullAddressSection: View {
    @Environment(\.palette) private var palette
    let address: Address

    var body: some View {
        Section {
            FullAddress(text: address.value)
                .foregroundStyle(palette.primaryText)
        } header: {
            Text("Address")
        } footer: {
            Text("Touch and hold the address to copy it.")
                .foregroundStyle(palette.secondaryText)
        }
        .listRowBackground(palette.surface)
    }
}
