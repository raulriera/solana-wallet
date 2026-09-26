/// A Solana account paired with its address.
public struct AccountEntry: Decodable, Sendable {
    /// The base-58 encoded address of the account.
    public let address: String

    /// The account's state and decoded binary data.
    public let account: Account

    /// Creates an entry from an account and its address.
    ///
    /// - Parameters:
    ///   - address: The base-58 encoded address of the account.
    ///   - account: The account's state and decoded binary data.
    public init(address: String, account: Account) {
        self.address = address
        self.account = account
    }

    /// The field names in an encoded account entry.
    private enum CodingKeys: String, CodingKey {
        case address = "pubkey"
        case account
    }
}
