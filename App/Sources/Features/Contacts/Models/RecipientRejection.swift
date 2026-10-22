import Foundation

/// Why the recipient sheet can't use the pasted text, explained under it.
nonisolated enum RecipientRejection: Equatable {
    /// The pasted text isn't an address.
    case notAddress
    /// The address is the account payments leave from.
    case sendingAccount
    /// Another account or contact is already saved at the address.
    case alreadySaved

    /// Explains the rejection under the pasted text.
    var message: LocalizedStringResource {
        switch self {
        case .notAddress: "This isn't a valid address."
        case .sendingAccount: "This is the account you're sending from."
        case .alreadySaved: "This address is already saved."
        }
    }
}
