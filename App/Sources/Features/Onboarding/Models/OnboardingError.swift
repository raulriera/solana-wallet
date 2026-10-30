import Foundation

/// An error in wallet setup.
nonisolated enum OnboardingError: LocalizedError, Equatable {
    case preparationFailed
    case rateLimited
    case saveFailed
    case openFailed
    /// Earlier setup work is still releasing its draft.
    case stillFinishing

    var errorDescription: String? { String(localized: "Wallet Setup Unavailable") }

    var recoverySuggestion: String? {
        switch self {
        case .preparationFailed: String(localized: "Your wallet could not be prepared. Please try again.")
        case .rateLimited: String(localized: "Too many requests. Wait a moment, then try again.")
        case .saveFailed:
            String(localized: "Your wallet could not be saved. Your recovery words are still available. Please try again.")
        case .openFailed: String(localized: "Your wallet could not be opened. Please try again.")
        case .stillFinishing: String(localized: "Wallet setup is still finishing. Please try again.")
        }
    }
}
