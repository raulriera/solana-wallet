public import Foundation

/// An account's raw data, owner program, and lamport balance.
public struct Account: Decodable, Sendable {
    /// The address of the program that owns the account.
    public let owner: String
    /// The balance in lamports.
    public let lamports: UInt64
    public let executable: Bool
    public let data: Data

    /// Creates an account.
    ///
    /// - Parameters:
    ///   - owner: The owner program's address.
    ///   - lamports: The balance in lamports.
    ///   - executable: Whether the account is executable.
    ///   - data: The raw account bytes.
    public init(owner: String, lamports: UInt64, executable: Bool, data: Data) {
        self.owner = owner
        self.lamports = lamports
        self.executable = executable
        self.data = data
    }

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

    /// The field names of an account.
    private enum CodingKeys: String, CodingKey { case owner, lamports, executable, data }
}
