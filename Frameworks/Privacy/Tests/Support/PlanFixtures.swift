import CryptoKit
import ModularArithmetic
@testable import Privacy
import RPC
import Testing
import Transactions

/// Transact plans that the sender of zolana's published transfers, the Ed25519 rail, builds.
///
/// The random values are fixed: the published blinding seed and salt, padding blindings of a zero
/// byte and 31 copies of 0xd0 plus the slot, and padding payloads of 89 copies of 0xe0 plus the
/// slot.
enum PlanFixtures {
    /// Creates a SOL UTXO that the sender owns.
    ///
    /// - Parameters:
    ///   - lamports: The amount.
    ///   - treeID: The ID of the tree that holds the UTXO.
    ///   - blindingByte: The byte that repeats after the blinding's leading zero.
    /// - Returns: The UTXO.
    /// - Throws: A test failure if the fixture is missing or malformed, or an error if it can't be
    ///   read or decoded.
    static func utxo(lamports: UInt64, treeID: UInt16 = 0, blindingByte: UInt8 = 0xa1) throws -> UTXO {
        UTXO(
            owner: try CommitmentVectors.load().ed25519Rail.ownerHash(), mint: Array(repeating: 0, count: 32), amount: lamports,
            blinding: TransferVectors.blinding(blindingByte), treeID: treeID
        )
    }

    /// Returns the fixed random values of a plan.
    ///
    /// - Parameters:
    ///   - paddingInputs: The number of padding inputs.
    ///   - paddingOutputs: The number of padding outputs.
    /// - Returns: The random values.
    static func randomness(paddingInputs: Int, paddingOutputs: Int) -> TransactPlan.Randomness {
        TransactPlan.Randomness(
            blindingSeed: TransferVectors.blindingSeed, salt: TransferVectors.salt,
            paddingInputBlindings: (0..<paddingInputs).map { TransferVectors.blinding(0xd0 + UInt8($0)) },
            paddingOutputData: (0..<paddingOutputs).map { [UInt8](repeating: 0xe0 + UInt8($0), count: ConfidentialOutput.payloadLength) }
        )
    }

    /// Plans a transact with the fixed random values.
    ///
    /// - Parameters:
    ///   - utxos: The sender's UTXOs to spend.
    ///   - transferLamports: The amount for the published transfers' recipient, if any.
    ///   - withdrawal: The withdrawal, if any.
    ///   - outputTreeID: The ID of the output tree.
    ///   - paddingInputs: The number of padding inputs that the plan's shape leaves.
    ///   - paddingOutputs: The number of padding outputs that the plan's shape leaves.
    /// - Returns: The plan.
    /// - Throws: A test failure if a fixture is malformed, or an error if the plan can't be built.
    static func plan(
        spending utxos: [UTXO],
        transferLamports: UInt64?,
        withdrawal: ExternalData.Withdrawal? = nil,
        outputTreeID: UInt16 = 0,
        paddingInputs: Int = 0,
        paddingOutputs: Int = 0
    ) throws -> TransactPlan {
        try TransactPlan(
            spending: utxos, sender: TransferVectors.sender(),
            transfer: try transferLamports.map { TransactPlan.Transfer(recipient: try TransferVectors.recipient(), lamports: $0) },
            withdrawal: withdrawal, outputTreeID: outputTreeID,
            randomness: randomness(paddingInputs: paddingInputs, paddingOutputs: paddingOutputs)
        )
    }

    /// Creates the indexer's view of a plan's transact, with output i at leaf `firstLeaf` + i.
    ///
    /// - Parameters:
    ///   - plan: The plan.
    ///   - salt: The salt that the transaction publishes.
    ///   - signature: The transaction's signature.
    ///   - slot: The transaction's slot.
    ///   - firstLeaf: The position of the first output in the output tree.
    /// - Returns: The transaction.
    /// - Throws: A test failure if the plan has no inputs, or an error if the transaction viewing key
    ///   can't be derived.
    static func transaction(
        of plan: TransactPlan,
        salt: [UInt8] = TransferVectors.salt,
        signature: String = "transact",
        slot: UInt64 = 9,
        firstLeaf: UInt64 = 40
    ) throws -> ShieldedTransaction {
        let firstNullifier = try #require(plan.nullifiers.first)
        let viewingKey = try TransactionViewingKey.derive(viewingKey: TransferVectors.sender().viewingKey, firstNullifier: firstNullifier)
        let outputs = plan.outputs.enumerated().map { index, output in
            let viewTag = switch output.published.ownerTag {
            case .inline(let tag): tag
            case .payer: plan.payer.bytes
            }
            return ShieldedOutput(
                viewTag: viewTag, utxoHash: output.published.utxoHash.bigEndianBytes, treeID: plan.outputTreeID,
                leafIndex: firstLeaf + UInt64(index), payload: output.published.data
            )
        }
        return ShieldedTransaction(
            signature: signature, slot: slot, eventIndex: 0, transactionViewingKey: Array(viewingKey.publicKey.compressedRepresentation),
            salt: salt, outputs: outputs, nullifiers: plan.nullifiers.map(\.bigEndianBytes), isProofless: false
        )
    }

    /// Returns a withdrawal to the published transfers' relayed payer.
    ///
    /// - Parameter lamports: The amount.
    /// - Returns: The withdrawal.
    /// - Throws: A test failure if the address is malformed.
    static func withdrawal(lamports: UInt64) throws -> ExternalData.Withdrawal {
        ExternalData.Withdrawal(recipient: try Address(TransferVectors.transfers[1].payer), lamports: lamports)
    }
}
