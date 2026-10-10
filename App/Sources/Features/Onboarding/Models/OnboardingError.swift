import Foundation

/// A wallet setup error that onboarding explains in an alert, without recovery text or underlying errors.
nonisolated enum OnboardingError: LocalizedError, Equatable {
    /// The wallet's recovery or account couldn't be prepared.
    case preparationFailed
    /// The network is limiting the requests that find an imported wallet's accounts.
    case rateLimited
    /// The prepared wallet couldn't be saved; its recovery words stay available.
    case saveFailed
    /// The saved wallet couldn't be opened.
    case openFailed
    /// Earlier setup work is still releasing its draft.
    case stillFinishing

    /// The alert's title.
    var errorDescription: String? { String(localized: "Wallet Setup Unavailable") }

    /// The alert's explanation.
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
