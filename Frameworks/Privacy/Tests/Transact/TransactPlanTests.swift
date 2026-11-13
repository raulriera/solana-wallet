import CryptoKit
import Encoding
import ModularArithmetic
import Testing
import Transactions
@testable import Privacy

struct TransactPlanTests {
    @Test
    func `Transfers with change lay out the recipient and then the change`() throws {
        let plan = try PlanFixtures.plan(spending: [PlanFixtures.utxo(lamports: 10)], transferLamports: 4)
        let recipient = try TransferVectors.recipient()

        #expect(plan.shape == Shape(inputs: 1, outputs: 2))
        #expect(plan.outputs.map { $0.utxo?.amount } == [4, 6])
        #expect(plan.outputs.map(\.published.ownerTag) == [.inline(recipient.viewTag), .payer])
        #expect(plan.inputs.map { $0.utxo == nil } == [false])
    }

    @Test
    func `Recipients receive the transfer`() throws {
        let plan = try PlanFixtures.plan(spending: [PlanFixtures.utxo(lamports: 10)], transferLamports: 4)
        let transactionViewingKey = try TransactionViewingKey.derive(
            viewingKey: TransferVectors.sender().viewingKey, firstNullifier: #require(plan.nullifiers.first)
        )

        let received = try ConfidentialOutput(decoding: plan.outputs[0].published.data).receive(
            viewingKey: TransferVectors.recipientViewingKey(), owner: TransferVectors.recipient().owner,
            transactionViewingPublicKey: transactionViewingKey.publicKey, salt: TransferVectors.salt, slot: 0,
            treeID: plan.outputTreeID, utxoHash: plan.commitments[0]
        )

        #expect(received?.amount == 4)
        #expect(received == plan.outputs[0].utxo)
    }

    @Test
    func `Senders receive the change`() throws {
        let plan = try PlanFixtures.plan(spending: [PlanFixtures.utxo(lamports: 10)], transferLamports: 4)
        let sender = try TransferVectors.sender()
        let transactionViewingKey = try TransactionViewingKey.derive(viewingKey: sender.viewingKey, firstNullifier: #require(plan.nullifiers.first))

        let received = try ConfidentialOutput(decoding: plan.outputs[1].published.data).receive(
            viewingKey: sender.viewingKey, owner: CommitmentVectors.load().ed25519Rail.ownerHash(),
            transactionViewingPublicKey: transactionViewingKey.publicKey, salt: TransferVectors.salt, slot: 1,
            treeID: plan.outputTreeID, utxoHash: plan.commitments[1]
        )

        #expect(received?.amount == 6)
        #expect(received == plan.outputs[1].utxo)
    }

    @Test
    func `Transfers without change pad with the recipient's view tag`() throws {
        let plan = try PlanFixtures.plan(spending: [PlanFixtures.utxo(lamports: 10)], transferLamports: 10, outputTreeID: 5, paddingOutputs: 1)
        let recipient = try TransferVectors.recipient()
        let padding = try #require(plan.outputs.last)

        #expect(padding.utxo == nil)
        #expect(padding.published.ownerTag == .inline(recipient.viewTag))
        #expect(padding.published.data == [UInt8](repeating: 0xe0, count: ConfidentialOutput.payloadLength))
    }

    @Test
    func `Withdrawals of every lamport give the sender a zero-amount output`() throws {
        let plan = try PlanFixtures.plan(
            spending: [PlanFixtures.utxo(lamports: 10)], transferLamports: nil, withdrawal: PlanFixtures.withdrawal(lamports: 10), paddingOutputs: 1
        )

        #expect(plan.shape == Shape(inputs: 1, outputs: 2))
        #expect(plan.outputs.map { $0.utxo?.amount } == [0, nil])
        #expect(plan.outputs.map(\.published.ownerTag) == [.payer, .payer])
        #expect(plan.withdrawal == (try PlanFixtures.withdrawal(lamports: 10)))
    }

    @Test
    func `Padding inputs join the last declared tree`() throws {
        let utxos = try [3, 1, 3, 1, 3, 1, 1].enumerated().map { index, tree in
            try PlanFixtures.utxo(lamports: 1, treeID: UInt16(tree), blindingByte: 0xb0 + UInt8(index))
        }
        let plan = try PlanFixtures.plan(spending: utxos, transferLamports: 7, outputTreeID: 2, paddingInputs: 1, paddingOutputs: 1)
        let padding = try #require(plan.inputs.last)

        #expect(plan.shape == Shape(inputs: 8, outputs: 2))
        #expect(plan.inputTreeIDs == [3, 1])
        #expect(plan.inputs.map(\.treeIndex) == [0, 1, 0, 1, 0, 1, 1, 1])
        #expect(padding.utxo == nil)
        #expect(plan.inputTreeIDs[Int(padding.treeIndex)] == 1)
    }

    @Test
    func `Plans keep the witness values`() throws {
        let utxos = try (0..<7).map { try PlanFixtures.utxo(lamports: 1, blindingByte: 0xb0 + UInt8($0)) }
        let plan = try PlanFixtures.plan(spending: utxos, transferLamports: 7, paddingInputs: 1, paddingOutputs: 1)

        #expect(plan.blindingSeed == TransferVectors.blindingSeed)
        #expect(plan.inputs.map(\.blinding) == (0..<7).map { TransferVectors.blinding(0xb0 + UInt8($0)) } + [TransferVectors.blinding(0xd0)])
        #expect(plan.outputs.map { $0.owner?.signingAddress } == [try TransferVectors.recipient().signingAddress, nil])
    }

    @Test
    func `Spent inputs publish the sender's nullifiers in order`() throws {
        let utxos = try [PlanFixtures.utxo(lamports: 6, treeID: 3, blindingByte: 0xb1), PlanFixtures.utxo(lamports: 5, treeID: 1, blindingByte: 0xb2)]
        let plan = try PlanFixtures.plan(spending: utxos, transferLamports: 4, outputTreeID: 2)

        #expect(plan.nullifiers == (try TransferVectors.spentInputs[1...2].map { try Poseidon.Element(hex: $0.nullifier) }))
    }

    @Test
    func `Random values give the same plan as explicit ones`() throws {
        let utxos = [try PlanFixtures.utxo(lamports: 10)]
        let transfer = TransactPlan.Transfer(recipient: try TransferVectors.recipient(), lamports: 10)
        var generator = SeededGenerator(seed: 7)
        let random = try TransactPlan(
            spending: utxos, sender: TransferVectors.sender(), transfer: transfer, withdrawal: nil, outputTreeID: 0, using: &generator
        )
        var replay = SeededGenerator(seed: 7)
        let randomness = TransactPlan.Randomness.random(paddingInputs: 0, paddingOutputs: 1, using: &replay)
        let explicit = try TransactPlan(
            spending: utxos, sender: TransferVectors.sender(), transfer: transfer, withdrawal: nil, outputTreeID: 0, randomness: randomness
        )

        #expect(random.outputs.map(\.published.data) == explicit.outputs.map(\.published.data))
        #expect(random.externalData.hash == explicit.externalData.hash)
        #expect(random.privateTransactionHash == explicit.privateTransactionHash)
        #expect(randomness.blindingSeed.bigEndianBytes[0] == 0)
        #expect(randomness.salt.count == 16)
        #expect(randomness.paddingOutputData.map(\.count) == [ConfidentialOutput.payloadLength])
    }

    @Test(arguments: [
        ([0], 0, [0]), ([1], 0, [0, 1]), ([1, 2], 0, [0, 1, 2]), ([0, 1], 1, [0, 1]),
    ] as [([UInt16], UInt16, Set<UInt16>)])
    func `Written trees are the input trees and the output tree, each once`(
        inputs: [UInt16], output: UInt16, written: Set<UInt16>
    ) {
        #expect(TransactPlan.writtenTreeIDs(inputs: inputs, output: output) == written)
    }

    @Test(arguments: [
        ([], 1, nil, .noInputs),
        (Array(repeating: (1, 0), count: 41), 1, nil, .tooManyInputs),
        ([(10, 0), (10, 1), (10, 2)], 1, nil, .tooManyInputTrees),
        ([(10, 0)], nil, nil, .nothingToSend),
        ([(10, 0)], 11, nil, .insufficientFunds),
        ([(10, 0)], 6, 5, .insufficientFunds),
        ([(.max, 0), (1, 0)], 1, nil, .amountOverflow),
        ([(10, 0)], .max, 1, .amountOverflow),
    ] as [([(UInt64, UInt16)], UInt64?, UInt64?, TransactPlan.ValidationError)])
    func `Invalid plans are rejected`(
        inputs: [(UInt64, UInt16)],
        transferLamports: UInt64?,
        withdrawalLamports: UInt64?,
        error: TransactPlan.ValidationError
    ) throws {
        let utxos = try inputs.map { try PlanFixtures.utxo(lamports: $0.0, treeID: $0.1) }
        let withdrawal = try withdrawalLamports.map { try PlanFixtures.withdrawal(lamports: $0) }

        #expect(throws: error) {
            try PlanFixtures.plan(spending: utxos, transferLamports: transferLamports, withdrawal: withdrawal)
        }
    }

    @Test(arguments: [(0, nil), (nil, 0)] as [(UInt64?, UInt64?)])
    func `Zero amounts are rejected`(transferLamports: UInt64?, withdrawalLamports: UInt64?) throws {
        let withdrawal = try withdrawalLamports.map { try PlanFixtures.withdrawal(lamports: $0) }

        #expect(throws: ValidationError.invalidAmount) {
            try PlanFixtures.plan(spending: [PlanFixtures.utxo(lamports: 10)], transferLamports: transferLamports, withdrawal: withdrawal)
        }
    }

    @Test
    func `Forty inputs fit the widest shape`() throws {
        let plan = try PlanFixtures.plan(spending: Array(repeating: PlanFixtures.utxo(lamports: 1), count: 40), transferLamports: 1)

        #expect(plan.shape == Shape(inputs: 40, outputs: 2))
    }

    @Test
    func `Inputs of other owners are rejected`() throws {
        let foreign = UTXO(
            owner: try TransferVectors.recipient().owner, mint: Array(repeating: 0, count: 32), amount: 10,
            blinding: TransferVectors.blinding(0xa1), treeID: 0
        )

        #expect(throws: TransactPlan.ValidationError.foreignInput) {
            try PlanFixtures.plan(spending: [foreign], transferLamports: 4)
        }
    }

    @Test
    func `Inputs of other assets are rejected`() throws {
        let token = UTXO(
            owner: try CommitmentVectors.load().ed25519Rail.ownerHash(), mint: Array(repeating: 1, count: 32), amount: 10,
            blinding: TransferVectors.blinding(0xa1), treeID: 0
        )

        #expect(throws: TransactPlan.ValidationError.unsupportedAsset) {
            try PlanFixtures.plan(spending: [token], transferLamports: 4)
        }
    }

    @Test
    func `Off-curve senders are rejected`() throws {
        let rail = try CommitmentVectors.load().ed25519Rail
        let sender = try ShieldedAccount(
            signingAddress: ShieldedPool.solInterface, nullifierSecret: rail.nullifierSecretKey(),
            viewingKey: rail.viewingKey()
        )

        #expect(throws: Recipient.ValidationError.offCurveSigningAddress) {
            try TransactPlan(
                spending: [PlanFixtures.utxo(lamports: 10)], sender: sender, transfer: nil, withdrawal: nil, outputTreeID: 0,
                randomness: PlanFixtures.randomness(paddingInputs: 0, paddingOutputs: 1)
            )
        }
    }
}

struct TransactPlanOwnerTagTests {
    @Test(arguments: try DummyOwnerTagVectors.load().selfPaidCases)
    func `Participants use the vectors' encodings`(_ vector: DummyOwnerTagVectors.Case) throws {
        let vectors = try DummyOwnerTagVectors.load()
        let sender = try Self.account(seed: vectors.senderSeed)
        let recipient = try Self.account(seed: vectors.recipientSeed).recipient
        let utxo = UTXO(owner: try sender.recipient.owner, mint: Array(repeating: 0, count: 32), amount: vectors.inputAmount,
                        blinding: TransferVectors.blinding(0xa1), treeID: 0)
        let resolved = try fixtureBytes(vector.resolved)
        let expected: TransactOutput.OwnerTag = vector.ownerTagKind == "account" ? .payer : .inline(resolved)
        var generator = SeededGenerator(seed: 432)

        let plan = try TransactPlan(
            spending: [utxo], sender: sender, transfer: TransactPlan.Transfer(recipient: recipient, lamports: vector.sendAmount),
            withdrawal: nil, outputTreeID: 0, using: &generator
        )

        let participant = try #require(plan.outputs.first { $0.owner?.viewTag == resolved })
        #expect(participant.published.ownerTag == expected)
    }

    @Test
    func `Padding with the sender's view tag refers to the payer`() throws {
        let plan = try PlanFixtures.plan(
            spending: [PlanFixtures.utxo(lamports: 10)], transferLamports: nil, withdrawal: PlanFixtures.withdrawal(lamports: 4), paddingOutputs: 1
        )

        #expect(plan.outputs.map { $0.utxo?.amount } == [6, nil])
        #expect(plan.outputs.map(\.published.ownerTag) == [.payer, .payer])
    }

    private static func account(seed: UInt8) throws -> ShieldedAccount {
        let signing = try Curve25519.Signing.PrivateKey(rawRepresentation: [UInt8](repeating: seed, count: 32))
        return try ShieldedAccount(
            signingAddress: Address(Base58.encode(Array(signing.publicKey.rawRepresentation))),
            nullifierSecret: SymmetricKey(data: [UInt8](repeating: seed, count: 31)),
            viewingKey: Curve25519.KeyAgreement.PrivateKey(rawRepresentation: [UInt8](repeating: seed, count: 32))
        )
    }
}
