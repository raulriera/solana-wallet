import Foundation

/// Something to check about a recipient before paying them, because the payment could go somewhere the person
/// didn't intend.
nonisolated enum RecipientWarning: Hashable, Sendable {
    /// The address starts and ends like another address the person paid or saved, but differs in between, as
    /// address poisoning arranges.
    case lookAlike
    /// No key exists for the address, so only the program that derived it can move what it receives.
    case offCurve

    /// Explains what to check.
    var message: LocalizedStringResource {
        switch self {
        case .lookAlike: "This address starts and ends like one you've used, but it's different. Check every character."
        case .offCurve: "This address belongs to a program, not a person. Only that program can move what you send."
        }
    }

    /// The name of the SF Symbol that pictures the warning.
    var systemImage: String {
        switch self {
        case .lookAlike: "exclamationmark.triangle.fill"
        case .offCurve: "exclamationmark.circle.fill"
        }
    }
}
