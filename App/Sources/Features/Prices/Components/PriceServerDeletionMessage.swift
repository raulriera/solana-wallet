import SwiftUI

/// The message that asks the person to confirm a custom price server's deletion.
struct PriceServerDeletionMessage: View {
    let url: URL
    /// Whether the server is the price provider in use.
    let isSelected: Bool

    var body: some View {
        let host = Text(PriceSettings.Provider.custom(url).name)
        isSelected
            ? Text("\(host) will be deleted from this device, and every window will switch to the default price provider.",
                   comment: "The Delete Price Server confirmation's message for the server in use. The variable is the server's host.")
            : Text("\(host) will be deleted from this device.",
                   comment: "The Delete Price Server confirmation's message. The variable is the server's host.")
    }
}
