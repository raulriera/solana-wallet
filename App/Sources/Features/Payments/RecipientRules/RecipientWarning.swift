import Foundation

/// Something to check about a recipient before paying them.
nonisolated enum RecipientWarning: Hashable, Sendable {
    /// The address starts and ends like another address the person used, but differs in between.
    case lookAlike
    /// No key exists for the address.
    case offCurve
    case firstPayment

    var message: LocalizedStringResource {
        switch self {
        case .lookAlike: "This address starts and ends like one you've used, but it's different. Check every character."
        case .offCurve: "This address belongs to a program, not a person. Only that program can move what you send."
        case .firstPayment: "You haven't paid this address before."
        }
    }

    var systemImage: String {
        switch self {
        case .lookAlike: "exclamationmark.triangle.fill"
        case .offCurve: "exclamationmark.circle.fill"
        case .firstPayment: "person.fill.questionmark"
        }
    }

    /// Whether the payment could go somewhere the person didn't intend.
    var isSerious: Bool { self != .firstPayment }
}
