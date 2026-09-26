public import Foundation

/// The balance, program ownership, and binary data of a Solana account.
public struct Account: Decodable, Sendable {
    /// The number of lamports assigned to the account.
    public let lamports: UInt64

    /// The base-58 encoded address of the program that owns the account.
    public let owner: String

    /// The account's decoded binary data.
    public let data: Data

    /// A Boolean value that indicates whether the account contains an executable program.
    public let isExecutable: Bool

    /// The epoch at which the account next owes rent.
    public let rentEpoch: UInt64

    /// The account's data size in bytes, or `nil` if the node doesn't provide it.
    public let space: UInt64?

    /// Creates an account from its state and decoded data.
    ///
    /// - Parameters:
    ///   - lamports: The number of lamports assigned to the account.
    ///   - owner: The base-58 encoded address of the account's owning program.
    ///   - data: The account's decoded binary data.
    ///   - isExecutable: Whether the account contains an executable program.
    ///   - rentEpoch: The epoch at which the account next owes rent.
    ///   - space: The account's data size in bytes, or `nil` if unknown.
    public init(
        lamports: UInt64,
        owner: String,
        data: Data,
        isExecutable: Bool,
        rentEpoch: UInt64,
        space: UInt64?
    ) {
        self.lamports = lamports
        self.owner = owner
        self.data = data
        self.isExecutable = isExecutable
        self.rentEpoch = rentEpoch
        self.space = space
    }

    /// Creates an account by decoding its state and base64 data.
    ///
    /// - Parameter decoder: The decoder containing the account object.
    /// - Throws: A decoding error if a required field is missing or malformed,
    ///   or if the data isn't a valid base64 string paired with a `base64` label.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        lamports = try container.decode(UInt64.self, forKey: .lamports)
        owner = try container.decode(String.self, forKey: .owner)
        isExecutable = try container.decode(Bool.self, forKey: .isExecutable)
        rentEpoch = try container.decode(UInt64.self, forKey: .rentEpoch)
        space = try container.decodeIfPresent(UInt64.self, forKey: .space)

        var encodedData = try container.nestedUnkeyedContainer(forKey: .data)
        let text = try encodedData.decode(String.self)
        let encoding = try encodedData.decode(String.self)
        guard encoding == "base64", encodedData.isAtEnd, let data = Data(base64Encoded: text) else {
            throw DecodingError.dataCorruptedError(
                forKey: .data,
                in: container,
                debugDescription: "Expected a base64 string paired with its encoding label."
            )
        }
        self.data = data
    }

    /// The field names in an encoded account object.
    private enum CodingKeys: String, CodingKey {
        case lamports, owner, data, rentEpoch, space
        case isExecutable = "executable"
    }
}
