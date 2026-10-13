import Foundation

/// Why a provider entry screen asks for an API key or an RPC URL, which sets its wording.
nonisolated enum ProviderEntryPurpose: Hashable, Sendable {
    /// A first key, which connects the provider.
    case connect
    /// A first key added from Helius's details, which leaves the provider in use as it is.
    case add
    /// A new key, which replaces the saved key once it's checked.
    case change
    /// A custom RPC URL, which is added and chosen once it's checked.
    case customRPC

    /// The wording for key entry from Helius's details: adding a first key, or changing the saved one.
    /// - Parameter keyPreview: The saved key's preview, or `nil` when no key is saved.
    init(keyPreview: String?) {
        self = keyPreview == nil ? .add : .change
    }

    /// The screen's title.
    var title: LocalizedStringResource {
        switch self {
        case .connect: "Connect to Helius"
        case .add: "Add API Key"
        case .change: "Change API Key"
        case .customRPC: "Add Custom RPC"
        }
    }

    /// The entry section's header.
    var header: LocalizedStringResource {
        switch self {
        case .connect, .add: "API Key"
        case .change: "New API Key"
        case .customRPC: "URL"
        }
    }

    /// The entry section's footer, which says where the entry goes.
    var footer: LocalizedStringResource {
        switch self {
        case .connect: "Your key is stored only on this device and is sent only to Helius."
        case .add: "Your key is stored only on this device and is sent only to this provider."
        case .change:
            "The saved key stays until the new key is checked. Your key is stored only on this device and is sent only to this provider."
        case .customRPC:
            "Use your RPC's HTTPS URL. It must support live updates at the same URL. Custom RPCs serve mainnet. The URL stays on this device and is sent only to that RPC."
        }
    }

    /// The title of the action that checks and saves the entry.
    var action: LocalizedStringResource {
        switch self {
        case .connect: "Continue"
        case .add, .change: "Save"
        case .customRPC: "Add RPC"
        }
    }
}
