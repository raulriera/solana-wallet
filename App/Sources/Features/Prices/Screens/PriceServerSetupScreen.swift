import SwiftUI

/// Collects the URL of a custom price server.
struct PriceServerSetupScreen<Submission: ProviderSubmitting>: ProviderSetupScreen {
    let submission: Submission

    var body: some View {
        ProviderEntryForm(
            title: "Add Price Server",
            label: "Price Server URL",
            kind: .url,
            header: "URL",
            footer: "Use your server's HTTPS URL. It must answer with prices in this app's format. The URL stays on this device and is sent only to that server. Add only servers you trust.",
            action: "Add Server",
            submission: submission
        ) {} help: {}
    }
}

#Preview("Empty") {
    NavigationStack {
        PriceServerSetupScreen(submission: PreviewSubmission<CustomPriceError>(rejection: nil))
    }
    .tint(RenderedPalette(OriginalAppearance.palette).primary)
}

#Preview("Rejected") {
    NavigationStack {
        PriceServerSetupScreen(submission: PreviewSubmission(rejection: CustomPriceError.unreachable))
    }
    .tint(RenderedPalette(OriginalAppearance.palette).primary)
}
