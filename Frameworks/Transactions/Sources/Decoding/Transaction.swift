import Encoding
public import Foundation

/// The decoded contents of a V1 transaction, with unverified signatures.
public struct Transaction: Sendable, Equatable {
    /// The message bytes that every signature covers.
    public let message: Data
    /// The Base58 blockhash or durable nonce value encoded in the message.
    public let lifetimeSpecifier: String
    /// The accounts in wire order, starting with the fee payer and signers.
    public let accounts: [Account]
    public let requests: Requests
    public let instructions: [Instruction]
    /// The signatures in signer order, with zero-filled empty slots.
    public let signatures: [Data]

    /// The message bytes followed by the signature slots.
    public var serializedRepresentation: Data { signatures.reduce(message, +) }

    /// The first signature as Base58 text, or `nil` while the fee payer's slot is empty.
    public var signature: String? {
        guard let first = signatures.first, first.count == 64, first.contains(where: { $0 != 0 }) else { return nil }
        return Base58.encode(Array(first))
    }

    /// Creates a transaction.
    ///
    /// - Parameters:
    ///   - message: The message bytes.
    ///   - lifetimeSpecifier: The Base58 blockhash or durable nonce value.
    ///   - accounts: The accounts in wire order.
    ///   - requests: The fee and resource requests.
    ///   - instructions: The instructions in execution order.
    ///   - signatures: The signature slots in signer order.
    public init(message: Data, lifetimeSpecifier: String, accounts: [Account], requests: Requests,
                instructions: [Instruction], signatures: [Data]) {
        self.message = message
        self.lifetimeSpecifier = lifetimeSpecifier
        self.accounts = accounts
        self.requests = requests
        self.instructions = instructions
        self.signatures = signatures
    }

    /// An account and the privileges the message requests for it.
    public struct Account: Sendable, Equatable {
        public let address: Address
        public let isSigner: Bool
        public let isWritable: Bool

        /// Creates an account description.
        ///
        /// - Parameters:
        ///   - address: The account address.
        ///   - isSigner: Whether the message requires its signature.
        ///   - isWritable: Whether the message requests write access.
        public init(address: Address, isSigner: Bool, isWritable: Bool) {
            self.address = address
            self.isSigner = isSigner
            self.isWritable = isWritable
        }

        /// Returns an account that the message requests write access to.
        ///
        /// - Parameters:
        ///   - address: The account address.
        ///   - isSigner: Whether the message requires its signature.
        /// - Returns: The writable account.
        public static func writable(_ address: Address, isSigner: Bool = false) -> Self {
            Self(address: address, isSigner: isSigner, isWritable: true)
        }

        /// Returns an account that the message only reads.
        ///
        /// - Parameters:
        ///   - address: The account address.
        ///   - isSigner: Whether the message requires its signature.
        /// - Returns: The read-only account.
        public static func readonly(_ address: Address, isSigner: Bool = false) -> Self {
            Self(address: address, isSigner: isSigner, isWritable: false)
        }
    }

    /// The V1 configuration fields as encoded, with `nil` for omitted ones.
    public struct Requests: Sendable, Equatable {
        /// The total priority fee, excluding the base fee.
        public let priorityFeeLamports: UInt64?
        public let computeUnitLimit: UInt32?
        /// The maximum loaded account data size, in bytes.
        public let loadedAccountsDataSizeLimit: UInt32?
        /// The heap size in bytes.
        public let heapSize: UInt32?

        /// Creates requests.
        ///
        /// - Parameters:
        ///   - priorityFeeLamports: The total priority fee in lamports, or `nil` if omitted.
        ///   - computeUnitLimit: The compute unit limit, or `nil` if omitted.
        ///   - loadedAccountsDataSizeLimit: The account data size limit in bytes, or `nil` if omitted.
        ///   - heapSize: The heap size in bytes, or `nil` if omitted.
        public init(priorityFeeLamports: UInt64?, computeUnitLimit: UInt32?,
                    loadedAccountsDataSizeLimit: UInt32?, heapSize: UInt32?) {
            self.priorityFeeLamports = priorityFeeLamports
            self.computeUnitLimit = computeUnitLimit
            self.loadedAccountsDataSizeLimit = loadedAccountsDataSizeLimit
            self.heapSize = heapSize
        }
    }

    /// A program invocation that refers to the transaction's accounts by index.
    public struct Instruction: Sendable, Equatable {
        public let programIndex: Int
        public let accountIndices: [Int]
        public let data: Data

        /// Creates an instruction description.
        ///
        /// - Parameters:
        ///   - programIndex: The program's account index.
        ///   - accountIndices: The account indices, in order.
        ///   - data: The instruction data.
        public init(programIndex: Int, accountIndices: [Int], data: Data) {
            self.programIndex = programIndex
            self.accountIndices = accountIndices
            self.data = data
        }
    }
}
