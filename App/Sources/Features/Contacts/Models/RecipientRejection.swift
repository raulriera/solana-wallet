import Foundation

/// A reason the recipient sheet can't use pasted text.
nonisolated enum RecipientRejection: Equatable {
    case notAddress
    /// The address is the account that pays.
    case sendingAccount
    /// Another account or contact is saved at the address.
    case alreadySaved

    var message: LocalizedStringResource {
        switch self {
        case .notAddress: "This isn't a valid address."
        case .sendingAccount: "This is the account you're sending from."
        case .alreadySaved: "This address is already saved."
        }
    }
}
