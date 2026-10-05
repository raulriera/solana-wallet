import Foundation

/// A provider setup failure that never contains the entered key.
nonisolated enum ProviderConnectionError: Error, Equatable {
    /// The key is empty, or the provider rejected it.
    case invalidKey
    /// The provider is limiting requests; the user decides when to try again.
    case rateLimited
    /// The provider couldn't be reached or returned an unexpected response.
    case unavailable
    /// The accepted key couldn't be saved on this device.
    case storageFailed

    /// Explains the failure to the person setting up the provider, without the key or underlying error text.
    var message: LocalizedStringResource {
        switch self {
        case .invalidKey: "Helius didn't accept this API key. Check it and try again."
        case .rateLimited: "Helius is limiting requests right now. Please try again in a moment."
        case .unavailable: "Helius couldn't be reached. Check your connection and try again."
        case .storageFailed: "Your API key couldn't be saved. Please try again."
        }
    }
}
