import Encoding
public import Foundation

/// A request for a finalized transaction's execution outcome and the programs and data of its instructions.
public struct GetTransaction: RPCRequest {
    public static let method = "getTransaction"

    public static let maximumResponseLength: Int? = 1_048_576

    /// The longest instruction data, in bytes, that a V1 transaction holds.
    private static let maximumInstructionLength = 4_096

    /// The transaction, or `nil` if the node hasn't finalized it or doesn't hold it.
    public typealias Response = Value?

    /// A finalized transaction's execution outcome and the programs and data of its instructions.
    public struct Value: Decodable, Sendable, Equatable {
        /// The execution error, or `nil` if the transaction succeeded.
        public let error: TransactionError?

        /// Each top-level instruction followed by the instructions that programs invoked while it ran, in execution
        /// order.
        private let instructions: [EncodedInstruction]

        public init(from decoder: any Decoder) throws {
            let payload = try Payload(from: decoder)
            let message = payload.transaction.message
            let loaded = payload.meta.loadedAddresses
            let programs = message.accountKeys + (loaded?.writable ?? []) + (loaded?.readonly ?? [])
            let inner = Dictionary(grouping: payload.meta.innerInstructions ?? [], by: \.index)
            let compiled = message.instructions.indices.flatMap { index in
                [message.instructions[index]] + (inner[index] ?? []).flatMap(\.instructions)
            }
            guard inner.keys.allSatisfy(message.instructions.indices.contains),
                  compiled.allSatisfy({ programs.indices.contains($0.programIdIndex) }) else {
                throw DecodingError.dataCorrupted(
                    DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "An instruction names a missing program.")
                )
            }
            error = payload.meta.error
            instructions = compiled.map { EncodedInstruction(program: programs[$0.programIdIndex], data: $0.data) }
        }

        /// Returns the data of the instructions that invoke a program, top-level and invoked, in execution order.
        ///
        /// - Parameter program: The program's base-58 address.
        /// - Returns: The data of each of the program's instructions that holds valid base-58 data no longer than a V1
        ///   transaction.
        public func instructionData(invoking program: String) -> [Data] {
            instructions.filter { $0.program == program }.compactMap { instruction in
                Base58.decode(instruction.data, maximumCount: GetTransaction.maximumInstructionLength).map { Data($0) }
            }
        }
    }

    /// An instruction's program and its undecoded data.
    private struct EncodedInstruction: Sendable, Equatable {
        /// The base-58 address of the invoked program.
        let program: String
        /// The base-58 instruction data.
        let data: String
    }

    /// A transaction's status metadata and signed contents.
    private struct Payload: Decodable {
        let meta: Meta
        let transaction: SignedTransaction
    }

    /// A transaction's execution outcome, its lookup-table addresses, and the instructions that programs invoked.
    private struct Meta: Decodable {
        let error: TransactionError?
        let loadedAddresses: LoadedAddresses?
        let innerInstructions: [InnerInstructions]?

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            error = try container.decode(TransactionError?.self, forKey: .error)
            loadedAddresses = try container.decodeIfPresent(LoadedAddresses.self, forKey: .loadedAddresses)
            innerInstructions = try container.decodeIfPresent([InnerInstructions].self, forKey: .innerInstructions)
        }

        /// The field names of a transaction's status metadata.
        private enum CodingKeys: String, CodingKey {
            case loadedAddresses, innerInstructions
            case error = "err"
        }
    }

    /// A transaction's signed contents.
    private struct SignedTransaction: Decodable {
        let message: Message
    }

    /// A transaction's accounts and top-level instructions.
    private struct Message: Decodable {
        let accountKeys: [String]
        let instructions: [CompiledInstruction]
    }

    /// The addresses that a transaction loaded from lookup tables.
    private struct LoadedAddresses: Decodable {
        let writable: [String]
        let readonly: [String]
    }

    /// The instructions that programs invoked while one top-level instruction ran.
    private struct InnerInstructions: Decodable {
        /// The position of the top-level instruction.
        let index: Int
        let instructions: [CompiledInstruction]
    }

    /// An instruction that names its program by index in the transaction's accounts.
    private struct CompiledInstruction: Decodable {
        let programIdIndex: Int
        /// The base-58 instruction data.
        let data: String
    }

    /// The base-58 signature of the transaction to read.
    public let signature: String

    /// Creates a read of a transaction at finalized commitment that accepts V1 transactions.
    ///
    /// - Parameter signature: The transaction's base-58 signature.
    public init(signature: String) {
        self.signature = signature
    }

    public func encode(to encoder: any Encoder) throws {
        var parameters = encoder.unkeyedContainer()
        try parameters.encode(signature)
        try parameters.encode(Configuration())
    }

    /// The commitment, encoding, and newest transaction version of the read.
    private struct Configuration: Encodable {
        let commitment = Commitment.finalized
        let encoding = "json"
        let maxSupportedTransactionVersion = 1
    }
}
