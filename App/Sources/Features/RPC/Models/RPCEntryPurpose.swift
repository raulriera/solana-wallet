import Foundation

/// The reason a provider entry screen asks for an API key or an RPC URL.
nonisolated enum RPCEntryPurpose: Hashable, Sendable {
    /// A first key that connects the provider.
    case connect
    /// A first key that leaves the provider in use as it is.
    case add
    /// A new key that replaces the saved key.
    case change
    case customRPC

    /// Creates the purpose of adding a first key or changing the saved one.
    ///
    /// - Parameter keyPreview: The saved key's preview, or `nil` when no key is saved.
    init(keyPreview: String?) {
        self = keyPreview == nil ? .add : .change
    }

    var title: LocalizedStringResource {
        switch self {
        case .connect: "Connect to Helius"
        case .add: "Add API Key"
        case .change: "Change API Key"
        case .customRPC: "Add Custom RPC"
        }
    }

    var header: LocalizedStringResource {
        switch self {
        case .connect, .add: "API Key"
        case .change: "New API Key"
        case .customRPC: "URL"
        }
    }

    var footer: LocalizedStringResource {
        switch self {
        case .connect: "Your key is stored only on this device and is sent only to Helius."
        case .add: "Your key is stored only on this device and is sent only to this provider."
        case .change:
            "The saved key stays until the new key is checked. Your key is stored only on this device and is sent only to this provider."
        case .customRPC:
            "Use your RPC's HTTPS URL. It must support live updates at the same URL. Custom RPCs serve mainnet. The URL stays on this device and is sent only to that RPC. Anyone can run an RPC. Add only RPCs you trust."
        }
    }

    /// The label of the entry's field.
    var label: LocalizedStringResource {
        self == .customRPC ? "RPC URL" : "RPC API key"
    }

    var kind: ProviderEntry.Kind {
        self == .customRPC ? .url : .key
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
