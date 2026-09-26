/// The shared configuration for reading account state and base64 data.
struct AccountConfiguration: Encodable {
    /// The confirmation level requested for the account state.
    let commitment: Commitment

    /// The encoding requested for the account's binary data.
    let encoding = "base64"
}
