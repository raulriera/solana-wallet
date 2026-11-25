import SwiftUI

/// Collects the URL of a custom price server.
struct PriceServerSetupScreen: ProviderSetupScreen {
    let submission: ProviderSetupModel<CustomPriceError>

    var body: some View {
        ProviderEntryForm(
            title: "Add Price Server",
            label: "Price Server URL",
            kind: .url,
            header: "URL",
            footer: "Add only servers you trust.",
            action: "Add Server",
            submission: submission
        ) {} help: {}
    }
}
