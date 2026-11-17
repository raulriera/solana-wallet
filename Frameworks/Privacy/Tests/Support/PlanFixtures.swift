import CryptoKit
import ModularArithmetic
import RPC
import Testing
import Transactions
@testable import Privacy

enum PlanFixtures {
    static func utxo(
        amount: UInt64, treeID: UInt16 = 0, blindingByte: UInt8 = 0xa1, asset: PrivateAsset
    ) throws -> UTXO {
        UTXO(
            owner: try CommitmentVectors.load().ed25519Rail.ownerHash(), asset: asset, amount: amount,
            blinding: TransferVectors.blinding(blindingByte), treeID: treeID
        )
    }

    static func randomness(paddingInputs: Int, paddingOutputs: Int) -> TransactPlan.Randomness {
        TransactPlan.Randomness(
            blindingSeed: TransferVectors.blindingSeed, salt: TransferVectors.salt,
            paddingInputBlindings: (0..<paddingInputs).map { TransferVectors.blinding(0xd0 + UInt8($0)) },
            paddingOutputData: (0..<paddingOutputs).map { [UInt8](repeating: 0xe0 + UInt8($0), count: ConfidentialOutput.payloadLength) }
        )
    }

    static func plan(
        spending utxos: [UTXO],
        of asset: PrivateAsset,
        transfer: UInt64?,
        withdrawal: ExternalData.Withdrawal? = nil,
        outputTreeID: UInt16 = 0,
        paddingInputs: Int = 0,
        paddingOutputs: Int = 0
    ) throws -> TransactPlan {
        try TransactPlan(
            spending: utxos, of: asset, sender: TransferVectors.sender(),
            transfer: try transfer.map { TransactPlan.Transfer(recipient: try TransferVectors.recipient(), amount: $0) },
            withdrawal: withdrawal, outputTreeID: outputTreeID,
            randomness: randomness(paddingInputs: paddingInputs, paddingOutputs: paddingOutputs)
        )
    }

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
            signature: signature, slot: slot, eventIndex: 0, transactionViewingKey: Array(viewingKey.publicKey.taggedRepresentation),
            salt: salt, outputs: outputs, nullifiers: plan.nullifiers.map(\.bigEndianBytes), isProofless: false
        )
    }

    static func withdrawal(_ amount: UInt64, of asset: PrivateAsset) throws -> ExternalData.Withdrawal {
        ExternalData.Withdrawal(recipient: try Address(TransferVectors.transfers[1].payer), amount: amount, asset: asset)
    }
}
