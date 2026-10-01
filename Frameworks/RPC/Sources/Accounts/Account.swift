public import Foundation

/// Raw Solana account data with its owner program and lamport balance.
public struct Account: Decodable, Sendable {
    /// The account's program owner, not the authority encoded within token data.
    public let owner: String
    /// The account's SOL balance in integer lamports.
    public let lamports: UInt64
    /// Whether the account contains executable program code.
    public let executable: Bool
    /// The exact bytes decoded from the requested base64 representation.
    public let data: Data

    /// Creates an account observation without interpreting its program data.
    ///
    /// - Parameters:
    ///   - owner: The owner program's address.
    ///   - lamports: The account's lamport balance.
    ///   - executable: Whether the account is executable.
    ///   - data: The raw account bytes.
    public init(owner: String, lamports: UInt64, executable: Bool, data: Data) {
        self.owner = owner
        self.lamports = lamports
        self.executable = executable
        self.data = data
    }

    /// Decodes only the base64 representation requested by the account RPC contract.
    ///
    /// - Parameter decoder: The account object supplied by the provider.
    /// - Throws: A decoding error for malformed or unexpected account representations.
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        owner = try values.decode(String.self, forKey: .owner)
        lamports = try values.decode(UInt64.self, forKey: .lamports)
        executable = try values.decode(Bool.self, forKey: .executable)
        let encoded = try values.decode([String].self, forKey: .data)
        guard encoded.count == 2, encoded[1] == "base64", let bytes = Data(base64Encoded: encoded[0]) else {
            throw DecodingError.dataCorruptedError(forKey: .data, in: values, debugDescription: "Invalid account encoding.")
        }
        data = bytes
    }

    private enum CodingKeys: String, CodingKey { case owner, lamports, executable, data }
}
