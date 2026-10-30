import Foundation

/// A reason a provider API key couldn't be checked or saved.
nonisolated enum ProviderConnectionError: ProviderEntryError {
    /// The key is empty, or the provider rejected it.
    case invalidKey
    case rateLimited
    /// The provider couldn't be reached or returned an unexpected response.
    case unavailable
    /// The key couldn't be saved.
    case storageFailed

    var rejectsEntry: Bool { self == .invalidKey }

    var errorDescription: String? {
        switch self {
        case .invalidKey: String(localized: "API Key Not Accepted")
        case .rateLimited: String(localized: "Too Many Requests")
        case .unavailable: String(localized: "Couldn't Connect")
        case .storageFailed: String(localized: "Couldn't Save API Key")
        }
    }

    var message: LocalizedStringResource {
        switch self {
        case .invalidKey: "Your provider didn't accept this API key. Check it and try again."
        case .rateLimited: "Your provider is limiting requests. Wait a moment, then try again."
        case .unavailable: "Your provider couldn't be reached. Check your connection and try again."
        case .storageFailed: "Your API key couldn't be saved. Please try again."
        }
    }
}
