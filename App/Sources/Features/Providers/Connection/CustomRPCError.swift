import Foundation

/// Why a custom RPC couldn't be added; it never contains the URL, which can hold a key.
nonisolated enum CustomRPCError: ProviderEntryError {
    /// The text isn't an HTTPS URL with a host.
    case notHTTPS
    /// The RPC is already in the list.
    case duplicate
    /// The URL didn't answer a standard Solana request.
    case unreachable
    /// The RPC didn't accept a live-updates subscription at the same URL.
    case noLiveUpdates
    /// The RPC is limiting requests; the person decides when to try again.
    case rateLimited
    /// The RPC couldn't be checked for another reason.
    case unavailable
    /// The checked RPC couldn't be saved on this device.
    case storageFailed

    /// Whether the URL itself was refused, so the screen explains it under the field.
    var rejectsEntry: Bool {
        switch self {
        case .notHTTPS, .duplicate, .unreachable, .noLiveUpdates: true
        case .rateLimited, .unavailable, .storageFailed: false
        }
    }

    /// Names the failure in an alert's title.
    var errorDescription: String? {
        switch self {
        case .notHTTPS, .duplicate, .unreachable, .noLiveUpdates: String(localized: "Couldn't Add RPC")
        case .rateLimited: String(localized: "Too Many Requests")
        case .unavailable: String(localized: "Couldn't Check RPC")
        case .storageFailed: String(localized: "Couldn't Save RPC")
        }
    }

    /// Explains the failure in an alert's message.
    var recoverySuggestion: String? { String(localized: message) }

    /// Explains the failure without the URL or underlying error text.
    var message: LocalizedStringResource {
        switch self {
        case .notHTTPS: "Enter a full URL that starts with https://."
        case .duplicate: "This RPC is already in your list."
        case .unreachable: "This URL didn't answer as a Solana RPC. Check it and your connection, then try again."
        case .noLiveUpdates: "This RPC doesn't support live updates at the same URL. Use one that does."
        case .rateLimited: "This RPC is limiting requests right now. Try again in a moment."
        case .unavailable: "This RPC couldn't be checked. Try again."
        case .storageFailed: "The RPC couldn't be saved on this device. Try again."
        }
    }
}
