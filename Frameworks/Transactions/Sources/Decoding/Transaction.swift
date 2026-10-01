import Encoding
public import Foundation

/// The structural contents of a V1 transaction, with unverified signature slots.
///
/// This value doesn't establish authorization, execution success, or instruction
/// meaning. The lifetime specifier alone doesn't identify a network or expiry height.
public struct Transaction: Sendable, Equatable {
    /// The exact bytes covered by every signature, excluding the signature array.
    public let message: Data
    /// The Base58 blockhash or durable nonce value encoded in the message.
    public let lifetimeSpecifier: String
    /// The accounts in wire order, beginning with the fee payer and required signers.
    public let accounts: [Account]
    /// The optional fee and resource requests as encoded, without clamping or defaults.
    public let requests: Requests
    /// The instructions in execution order, with their uninterpreted payloads.
    public let instructions: [Instruction]
    /// The unverified signatures in required-signer order, including zero-filled slots.
    public let signatures: [Data]

    /// The original message followed by its ordered signature slots, without re-encoding fields.
    ///
    /// This representation doesn't validate fields supplied through the initializer.
    public var serializedRepresentation: Data { signatures.reduce(message, +) }

    /// The first signature as Base58 text, or `nil` while the fee payer's slot is empty.
    ///
    /// This identifier doesn't establish signature validity or submission status.
    public var signature: String? {
        guard let first = signatures.first, first.count == 64, first.contains(where: { $0 != 0 }) else { return nil }
        return Base58.encode(Array(first))
    }

    /// Creates inspection data without validating its supplied fields or signatures.
    ///
    /// - Parameters:
    ///   - message: The original unsigned message bytes.
    ///   - lifetimeSpecifier: The encoded blockhash or durable nonce value.
    ///   - accounts: The accounts and requested privileges in wire order.
    ///   - requests: The encoded fee and resource requests.
    ///   - instructions: The ordered program invocations and payloads.
    ///   - signatures: The corresponding signature slots, including missing signatures.
    public init(message: Data, lifetimeSpecifier: String, accounts: [Account], requests: Requests,
                instructions: [Instruction], signatures: [Data]) {
        self.message = message
        self.lifetimeSpecifier = lifetimeSpecifier
        self.accounts = accounts
        self.requests = requests
        self.instructions = instructions
        self.signatures = signatures
    }

    /// An account and the privileges requested by the message header.
    public struct Account: Sendable, Equatable {
        /// The account's validated, canonical Base58 address.
        public let address: Address
        /// Whether a corresponding signature slot is required for this account.
        public let isSigner: Bool
        /// Whether the header requests write access; the runtime may demote this privilege.
        public let isWritable: Bool

        /// Creates an account description without asserting runtime access or ownership.
        ///
        /// - Parameters:
        ///   - address: The account address.
        ///   - isSigner: Whether the message requires its signature.
        ///   - isWritable: Whether the header requests write access.
        public init(address: Address, isSigner: Bool, isWritable: Bool) {
            self.address = address
            self.isSigner = isSigner
            self.isWritable = isWritable
        }
    }

    /// The optional V1 configuration fields exactly as encoded on the wire.
    ///
    /// Unlike ``Configuration``, these preserve omitted and zero-valued requests.
    /// Omitted fee, compute, and account-data requests mean zero; omitted heap means 32 KiB.
    public struct Requests: Sendable, Equatable {
        /// The total priority fee in lamports, excluding the base fee, or `nil` if omitted.
        public let priorityFeeLamports: UInt64?
        /// The requested compute limit, or `nil` if omitted; this is not measured usage.
        public let computeUnitLimit: UInt32?
        /// The requested account-data limit in bytes, or `nil` if omitted.
        public let loadedAccountsDataSizeLimit: UInt32?
        /// The requested heap size in bytes, or `nil` if omitted.
        public let heapSize: UInt32?

        /// Creates encoded requests without validating or replacing their supplied values.
        ///
        /// - Parameters:
        ///   - priorityFeeLamports: The priority fee, including zero, or `nil` for omission.
        ///   - computeUnitLimit: The compute request, including zero, or `nil` for omission.
        ///   - loadedAccountsDataSizeLimit: The account-data request, or `nil` for omission.
        ///   - heapSize: The heap request, or `nil` for omission.
        public init(priorityFeeLamports: UInt64?, computeUnitLimit: UInt32?,
                    loadedAccountsDataSizeLimit: UInt32?, heapSize: UInt32?) {
            self.priorityFeeLamports = priorityFeeLamports
            self.computeUnitLimit = computeUnitLimit
            self.loadedAccountsDataSizeLimit = loadedAccountsDataSizeLimit
            self.heapSize = heapSize
        }
    }

    /// A program invocation whose data remains uninterpreted.
    public struct Instruction: Sendable, Equatable {
        /// The program's index in the transaction's account array.
        public let programIndex: Int
        /// The instruction's ordered account indices, retaining repeated entries.
        public let accountIndices: [Int]
        /// The exact instruction payload, without inferring its meaning.
        public let data: Data

        /// Creates an instruction description without validating its account indices.
        ///
        /// - Parameters:
        ///   - programIndex: The invoked program's account index.
        ///   - accountIndices: The account indices supplied to the program, in order.
        ///   - data: The instruction's opaque payload.
        public init(programIndex: Int, accountIndices: [Int], data: Data) {
            self.programIndex = programIndex
            self.accountIndices = accountIndices
            self.data = data
        }
    }
}
