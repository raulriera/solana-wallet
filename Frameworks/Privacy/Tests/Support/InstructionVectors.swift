import Testing
import Transactions

/// Deposit and transact instructions computed by an independent Python implementation written from
/// zolana v0.4.0-alpha's sources, with the padding owner tags of zolana's main branch (#432).
///
/// The deposits come from the sender of zolana's published transfers, or from their relayed payer,
/// to the published transfers' recipient or to the sender. The transacts use ``PlanFixtures``: its
/// sender, recipient, UTXOs, fixed random values, and withdrawals to the relayed payer. Their proof
/// fills `a`, `b`, and `c` with 1, 2, and 3. Data and hashes are hexadecimal; addresses are Base58.
struct InstructionVectors: Decodable, Sendable {
    /// The Base58 address of the shielded-pool program that every instruction invokes.
    let program: String

    /// The deposits.
    let deposits: [Deposit]

    /// The transacts.
    let transacts: [Transact]

    /// An account of an instruction and its permissions.
    struct Account: Decodable, Sendable {
        /// The account's Base58 address.
        let address: String
        /// Whether the account signs.
        let isSigner: Bool
        /// Whether the account is writable.
        let isWritable: Bool

        /// Creates the account as an instruction lists it.
        ///
        /// - Returns: The account.
        /// - Throws: An error if the address is malformed.
        func account() throws -> Transaction.Account {
            Transaction.Account(address: try Address(address), isSigner: isSigner, isWritable: isWritable)
        }
    }

    /// A deposit and its instruction.
    struct Deposit: Decodable, Sendable, CustomTestStringConvertible {
        /// The vector's name.
        let name: String
        /// The amount, as a decimal integer, since it may exceed a JSON number's precision.
        let lamports: String
        /// The depositor's Base58 address.
        let depositor: String
        /// Whether the sender receives the deposit instead of the published transfers' recipient.
        let toSender: Bool
        /// The ID of the tree that receives the UTXO.
        let treeID: UInt16
        /// The instruction data.
        let data: String
        /// The instruction's accounts, in order.
        let accounts: [Account]

        /// The vector's name, in test results.
        var testDescription: String { name }
    }

    /// A transact plan and its instruction.
    struct Transact: Decodable, Sendable, CustomTestStringConvertible {
        /// The vector's name.
        let name: String
        /// The spent UTXOs, in slot order.
        let inputs: [Input]
        /// The amount for the published transfers' recipient, if any.
        let transferLamports: UInt64?
        /// The amount withdrawn to the relayed payer, if any.
        let withdrawalLamports: UInt64?
        /// The ID of the output tree.
        let outputTreeID: UInt16
        /// The number of padding inputs.
        let paddingInputs: Int
        /// The number of padding outputs.
        let paddingOutputs: Int
        /// Each declared input tree's UTXO and nullifier root indexes.
        let treeContexts: [[UInt16]]
        /// The external data hash.
        let externalDataHash: String
        /// The private transaction hash.
        let privateTransactionHash: String
        /// The instruction data.
        let data: String
        /// The instruction's accounts, in order.
        let accounts: [Account]

        /// The vector's name, in test results.
        var testDescription: String { name }
    }

    /// A spent UTXO of the sender, as ``PlanFixtures/utxo(lamports:treeID:blindingByte:)`` builds it.
    struct Input: Decodable, Sendable {
        /// The amount.
        let lamports: UInt64
        /// The ID of the UTXO's tree.
        let treeID: UInt16
        /// The byte that repeats after the blinding's leading zero.
        let blindingByte: UInt8
    }

    /// Reads the fixture from the test bundle.
    ///
    /// - Returns: The instruction vectors.
    /// - Throws: A test failure if the resource is missing, or an error if it can't be read or decoded.
    static func load() throws -> Self {
        try fixture(named: "InstructionVectors")
    }
}
