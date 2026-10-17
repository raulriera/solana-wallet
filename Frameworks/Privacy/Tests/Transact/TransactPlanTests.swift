import CryptoKit
import Encoding
import ModularArithmetic
@testable import Privacy
import Testing
import Transactions

/// Verifies transact plans: their slots, notes, hashes, and rejections.
///
/// The sender is zolana's Ed25519 rail and the recipient is the published transfers' recipient. The
/// plans use the fixed random values of ``PlanFixtures``.
struct TransactPlanTests {
    /// Verifies a transfer with change: one input, the recipient's output in slot 0 tagged inline,
    /// and the change in slot 1 referring to the payer, in the cheapest shape without padding.
    @Test
    func `Transfers with change lay out the recipient and then the change`() throws {
        let plan = try PlanFixtures.plan(spending: [PlanFixtures.utxo(lamports: 10)], transferLamports: 4)
        let recipient = try TransferVectors.recipient()

        #expect(plan.shape == Shape(inputs: 1, outputs: 2))
        #expect(plan.outputs.map { $0.utxo?.amount } == [4, 6])
        #expect(plan.outputs.map(\.published.ownerTag) == [.inline(recipient.viewTag), .payer])
        #expect(plan.inputs.map { $0.utxo == nil } == [false])
    }

    /// Verifies that the recipient receives its UTXO from the payload of slot 0 with its own viewing
    /// key.
    @Test
    func `Recipients receive the transfer`() throws {
        let plan = try PlanFixtures.plan(spending: [PlanFixtures.utxo(lamports: 10)], transferLamports: 4)
        let transactionViewingKey = try TransactionViewingKey.derive(
            viewingKey: TransferVectors.sender().viewingKey, firstNullifier: #require(plan.nullifiers.first)
        )

        let received = try ConfidentialOutput(decoding: plan.payloads[0]).receive(
            viewingKey: TransferVectors.recipientViewingKey(), owner: TransferVectors.recipient().owner,
            transactionViewingPublicKey: transactionViewingKey.publicKey, salt: TransferVectors.salt, slot: 0,
            treeID: plan.outputTreeID, utxoHash: plan.commitments[0]
        )

        #expect(received?.amount == 4)
        #expect(received == plan.outputs[0].utxo)
    }

    /// Verifies that the sender receives the change from the payload of slot 1 with its own viewing
    /// key.
    @Test
    func `Senders receive the change`() throws {
        let plan = try PlanFixtures.plan(spending: [PlanFixtures.utxo(lamports: 10)], transferLamports: 4)
        let sender = try TransferVectors.sender()
        let transactionViewingKey = try TransactionViewingKey.derive(viewingKey: sender.viewingKey, firstNullifier: #require(plan.nullifiers.first))

        let received = try ConfidentialOutput(decoding: plan.payloads[1]).receive(
            viewingKey: sender.viewingKey, owner: CommitmentVectors.load().ed25519Rail.ownerHash(),
            transactionViewingPublicKey: transactionViewingKey.publicKey, salt: TransferVectors.salt, slot: 1,
            treeID: plan.outputTreeID, utxoHash: plan.commitments[1]
        )

        #expect(received?.amount == 6)
        #expect(received == plan.outputs[1].utxo)
    }

    /// Verifies a transfer of every lamport: no change, so the padding output carries the
    /// recipient's view tag, an empty-UTXO commitment, and the given payload.
    @Test
    func `Transfers without change pad with the recipient's view tag`() throws {
        let plan = try PlanFixtures.plan(spending: [PlanFixtures.utxo(lamports: 10)], transferLamports: 10, outputTreeID: 5, paddingOutputs: 1)
        let recipient = try TransferVectors.recipient()
        let firstNullifier = try #require(plan.nullifiers.first)
        let seed = TransactBlinding.outputBlindingSeed(firstNullifier: firstNullifier, blindingSeed: TransferVectors.blindingSeed)
        let padding = try #require(plan.outputs.last)

        #expect(padding.utxo == nil)
        #expect(padding.published.ownerTag == .inline(recipient.viewTag))
        #expect(padding.published.utxoHash == UTXO.dummyHash(
            treeID: 5, blinding: TransactBlinding.outputBlinding(firstNullifier: firstNullifier, outputBlindingSeed: seed, index: 1)
        ))
        #expect(padding.published.data == [UInt8](repeating: 0xe0, count: ConfidentialOutput.payloadLength))
    }

    /// Verifies a withdrawal of every lamport: no transfer and no change, so the sender gets a
    /// zero-amount output, and the padding output borrows the sender's view tag and, like the
    /// sender's output, refers to the payer for it.
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

    /// Verifies inputs from two trees: trees in first-use order, and padding inputs in the last
    /// declared tree with empty-UTXO hashes and nullifiers under the zero nullifier secret.
    @Test
    func `Padding inputs join the last declared tree`() throws {
        let utxos = try [3, 1, 3, 1, 3, 1, 1].enumerated().map { index, tree in
            try PlanFixtures.utxo(lamports: 1, treeID: UInt16(tree), blindingByte: 0xb0 + UInt8(index))
        }
        let plan = try PlanFixtures.plan(spending: utxos, transferLamports: 7, outputTreeID: 2, paddingInputs: 1, paddingOutputs: 1)
        let padding = try #require(plan.inputs.last)
        let zeroKey = try NullifierKey(secret: SymmetricKey(data: [UInt8](repeating: 0, count: 31)))

        #expect(plan.shape == Shape(inputs: 8, outputs: 2))
        #expect(plan.inputTreeIDs == [3, 1])
        #expect(plan.inputs.map(\.treeIndex) == [0, 1, 0, 1, 0, 1, 1, 1])
        #expect(padding.utxo == nil)
        #expect(plan.inputTreeIDs[Int(padding.treeIndex)] == 1)
        #expect(padding.hash == UTXO.dummyHash(treeID: 1, blinding: TransferVectors.blinding(0xd0)))
        #expect(padding.nullifier == zeroKey.nullifier(utxoHash: padding.hash, blinding: TransferVectors.blinding(0xd0)))
    }

    /// Verifies that a plan keeps the values that its proof's witness needs: the blinding seed, each
    /// slot's blinding, and each output's owner.
    @Test
    func `Plans keep the witness values`() throws {
        let utxos = try (0..<7).map { try PlanFixtures.utxo(lamports: 1, blindingByte: 0xb0 + UInt8($0)) }
        let plan = try PlanFixtures.plan(spending: utxos, transferLamports: 7, paddingInputs: 1, paddingOutputs: 1)
        let firstNullifier = try #require(plan.nullifiers.first)
        let seed = TransactBlinding.outputBlindingSeed(firstNullifier: firstNullifier, blindingSeed: TransferVectors.blindingSeed)

        #expect(plan.blindingSeed == TransferVectors.blindingSeed)
        #expect(plan.inputs.map(\.blinding) == (0..<7).map { TransferVectors.blinding(0xb0 + UInt8($0)) } + [TransferVectors.blinding(0xd0)])
        #expect(plan.outputs.map(\.blinding) == (0..<2).map {
            TransactBlinding.outputBlinding(firstNullifier: firstNullifier, outputBlindingSeed: seed, index: $0)
        })
        #expect(plan.outputs.map { $0.owner?.signingAddress } == [try TransferVectors.recipient().signingAddress, nil])
    }

    /// Verifies that spent inputs publish the sender's nullifiers in the caller's order.
    @Test
    func `Spent inputs publish the sender's nullifiers in order`() throws {
        let utxos = try [PlanFixtures.utxo(lamports: 6, treeID: 3, blindingByte: 0xb1), PlanFixtures.utxo(lamports: 5, treeID: 1, blindingByte: 0xb2)]
        let plan = try PlanFixtures.plan(spending: utxos, transferLamports: 4, outputTreeID: 2)

        #expect(plan.nullifiers == (try TransferVectors.spentInputs[1...2].map { try Poseidon.Element(hex: $0.nullifier) }))
    }

    /// Verifies that random values from a generator give the same plan as the same values passed
    /// directly, and that the drawn blindings stay below 2^248.
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

        #expect(random.payloads == explicit.payloads)
        #expect(random.externalData.hash == explicit.externalData.hash)
        #expect(random.privateTransactionHash == explicit.privateTransactionHash)
        #expect(randomness.blindingSeed.bigEndianBytes[0] == 0)
        #expect(randomness.salt.count == 16)
        #expect(randomness.paddingOutputData.map(\.count) == [ConfidentialOutput.payloadLength])
    }

    /// Verifies that printing, dumping, and reflecting a plan, its slots, its transfer, and its
    /// random values omit their values.
    @Test
    func `Plan diagnostics omit amounts and blindings`() throws {
        let plan = try PlanFixtures.plan(spending: [PlanFixtures.utxo(lamports: 10)], transferLamports: 4)
        let transfer = TransactPlan.Transfer(recipient: try TransferVectors.recipient(), lamports: 4)
        let randomness = PlanFixtures.randomness(paddingInputs: 1, paddingOutputs: 1)
        var output = ""
        dump(plan, to: &output)
        var randomnessOutput = ""
        dump(randomness, to: &randomnessOutput)

        #expect(String(reflecting: plan) == "TransactPlan")
        #expect(output == "- TransactPlan\n")
        #expect(Mirror(reflecting: plan).children.isEmpty)
        #expect(String(reflecting: plan.inputs[0]) == "TransactPlan.Input")
        #expect(String(reflecting: plan.outputs[0]) == "TransactPlan.Output")
        #expect(String(reflecting: transfer) == "TransactPlan.Transfer")
        #expect(Mirror(reflecting: transfer).children.isEmpty)
        #expect("\(randomness)" == "TransactPlan.Randomness")
        #expect(randomnessOutput == "- TransactPlan.Randomness\n")
        #expect(Mirror(reflecting: randomness).children.isEmpty)
    }

    /// Verifies the plans that can't be built.
    ///
    /// - Parameters:
    ///   - inputs: Each input's amount and tree.
    ///   - transferLamports: The transfer, if any.
    ///   - withdrawalLamports: The withdrawal, if any.
    ///   - error: The expected rejection.
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

    /// Verifies that a zero-lamport transfer or withdrawal is rejected.
    ///
    /// - Parameters:
    ///   - transferLamports: The transfer, if any.
    ///   - withdrawalLamports: The withdrawal, if any.
    @Test(arguments: [(0, nil), (nil, 0)] as [(UInt64?, UInt64?)])
    func `Zero amounts are rejected`(transferLamports: UInt64?, withdrawalLamports: UInt64?) throws {
        let withdrawal = try withdrawalLamports.map { try PlanFixtures.withdrawal(lamports: $0) }

        #expect(throws: ValidationError.invalidAmount) {
            try PlanFixtures.plan(spending: [PlanFixtures.utxo(lamports: 10)], transferLamports: transferLamports, withdrawal: withdrawal)
        }
    }

    /// Verifies that 40 inputs, zolana's wallet limit, fit the widest shape that a plan uses.
    @Test
    func `Forty inputs fit the widest shape`() throws {
        let plan = try PlanFixtures.plan(spending: Array(repeating: PlanFixtures.utxo(lamports: 1), count: 40), transferLamports: 1)

        #expect(plan.shape == Shape(inputs: 40, outputs: 2))
    }

    /// Verifies that inputs that another owner holds can't be spent.
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

    /// Verifies that inputs of assets other than SOL can't be spent.
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

    /// Verifies that a sender whose signing address is off the curve is rejected.
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

/// Verifies how outputs encode their view tags: participants as zolana's padding owner tag vectors
/// expect, and padding with the sender's view tag as a reference to the payer, like the sender's
/// own outputs, so an observer can't tell that padding from the sender's output.
struct TransactPlanOwnerTagTests {
    /// Verifies each self-paid case's participant encoding: the output whose view tag the vector's
    /// padding borrows uses the case's encoding. Plans always have the sender pay, so the sponsored
    /// case doesn't apply. Plans take the cheapest shape, not the vector's 8 output slots, so this
    /// test checks only the participant; the next test covers padding with the sender's view tag.
    ///
    /// - Parameter vector: A transfer and the encoding of the view tag that its padding borrows.
    /// - Throws: A test failure if the fixture is malformed, or an error if the plan can't be built.
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

    /// Verifies a withdrawal with change, whose padding borrows the sender's view tag, refers to the
    /// payer for it, as the sender's change does.
    ///
    /// - Throws: A test failure if a fixture is malformed, or an error if the plan can't be built.
    @Test
    func `Padding with the sender's view tag refers to the payer`() throws {
        let plan = try PlanFixtures.plan(
            spending: [PlanFixtures.utxo(lamports: 10)], transferLamports: nil, withdrawal: PlanFixtures.withdrawal(lamports: 4), paddingOutputs: 1
        )

        #expect(plan.outputs.map { $0.utxo?.amount } == [6, nil])
        #expect(plan.outputs.map(\.published.ownerTag) == [.payer, .payer])
    }

    /// Creates an account whose Ed25519 secret's 32 bytes all equal a seed, as zolana's vectors do.
    ///
    /// - Parameter seed: The repeated byte.
    /// - Returns: The account, with a nullifier secret and viewing key derived from the same seed.
    /// - Throws: An error if a key can't be created.
    private static func account(seed: UInt8) throws -> ShieldedAccount {
        let signing = try Curve25519.Signing.PrivateKey(rawRepresentation: [UInt8](repeating: seed, count: 32))
        return try ShieldedAccount(
            signingAddress: Address(Base58.encode(Array(signing.publicKey.rawRepresentation))),
            nullifierSecret: SymmetricKey(data: [UInt8](repeating: seed, count: 31)),
            viewingKey: P256.KeyAgreement.PrivateKey(rawRepresentation: [UInt8](repeating: seed, count: 32))
        )
    }
}
