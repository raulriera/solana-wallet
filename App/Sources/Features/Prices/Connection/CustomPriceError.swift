import Foundation

/// A reason a custom price server couldn't be added.
nonisolated enum CustomPriceError: ProviderEntryError {
    /// The text isn't an HTTPS URL with a host.
    case notHTTPS
    /// The price server is already in the list.
    case duplicate
    /// The URL didn't answer with a valid SOL price.
    case unreachable
    case rateLimited
    /// The price server couldn't be checked for another reason.
    case unavailable
    /// The price server couldn't be saved.
    case storageFailed

    var rejectsEntry: Bool {
        switch self {
        case .notHTTPS, .duplicate, .unreachable: true
        case .rateLimited, .unavailable, .storageFailed: false
        }
    }

    var errorDescription: String? {
        switch self {
        case .notHTTPS, .duplicate, .unreachable: String(localized: "Couldn't Add Price Server")
        case .rateLimited: String(localized: "Too Many Requests")
        case .unavailable: String(localized: "Couldn't Check Price Server")
        case .storageFailed: String(localized: "Couldn't Save Price Server")
        }
    }

    var message: LocalizedStringResource {
        switch self {
        case .notHTTPS: "Enter a full URL that starts with https://."
        case .duplicate: "This price server is already in your list."
        case .unreachable: "This URL didn't answer with a SOL price. Check it and your connection, then try again."
        case .rateLimited: "This price server is limiting requests right now. Try again in a moment."
        case .unavailable: "This price server couldn't be checked. Try again."
        case .storageFailed: "The price server couldn't be saved on this device. Try again."
        }
    }
}
