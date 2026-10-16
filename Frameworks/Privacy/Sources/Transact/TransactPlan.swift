import CryptoKit
import ModularArithmetic
import Transactions

/// A default-ring SOL transact before its proof: the sender spends UTXOs into a transfer, a public
/// withdrawal, or both, and keeps the change.
///
/// The plan follows zolana's `ConfidentialTransaction` with random padding:
///
/// - The plan transfers, withdraws, or both. It spends at most 40 inputs, zolana's wallet limit,
///   because wider shapes can exceed one transaction. The inputs keep the caller's order and declare
///   their trees in first-use order, at most two. Every input must be a SOL UTXO that the sender
///   owns.
/// - The outputs are the recipient's, then the sender's change if it's positive. If neither exists,
///   the sender gets a zero-amount output. The shape is the cheapest one that holds the inputs and
///   the outputs before that zero-amount output.
/// - Padding inputs are empty UTXOs in the last declared tree with random blindings, whose
///   nullifiers use the zero nullifier secret. Padding outputs are empty UTXOs in the output tree
///   with random payloads as long as a note, tagged with the sender's view tag, or the recipient's
///   if the sender has no output.
/// - Every output slot's blinding derives from the first nullifier and the blinding seed. Each real
///   output's note is sealed with the transaction viewing key and the salt. Outputs that the sender
///   owns refer to the fee payer, the sender, for their view tag.
///
/// Descriptions and reflection omit the amounts, the blindings, and the blinding seed.
struct TransactPlan: Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    /// A transact that the plan can't build.
    enum ValidationError: Error, Equatable {
        /// The plan spends no UTXOs.
        case noInputs
        /// The plan spends more UTXOs than one transaction holds.
        case tooManyInputs
        /// The plan has neither a transfer nor a withdrawal.
        case nothingToSend
        /// An input isn't owned by the sender.
        case foreignInput
        /// An input isn't SOL.
        case unsupportedAsset
        /// The inputs come from more than two trees.
        case tooManyInputTrees
        /// The inputs hold fewer lamports than the transfer and the withdrawal.
        case insufficientFunds
        /// A sum of lamports exceeds a 64-bit integer.
        case amountOverflow
        /// The tree contexts don't match the declared input trees one for one.
        case invalidTreeContextCount
        /// The nullifier key doesn't derive the spent inputs' nullifiers, so it isn't the sender's.
        case foreignNullifierKey
        /// The prover made the proof with a key other than the plan's shape's.
        case unexpectedProvingKey
        /// The prover resolved other trees than the plan declares, or in another order.
        case unexpectedTrees
        /// A resolved root's position is outside its tree's root history.
        case rootIndexOutOfRange
        /// A resolved root isn't a canonical field element.
        case invalidRoot
        /// The resolved roots don't reproduce the prover's public input hash.
        case publicInputHashMismatch
    }

    /// A transfer of SOL to another owner's shielded address.
    ///
    /// Descriptions and reflection omit the amount.
    struct Transfer: Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
        /// The owner who receives the SOL.
        let recipient: Recipient
        /// The positive amount, in lamports.
        let lamports: UInt64

        /// A description that omits the amount.
        var description: String { "TransactPlan.Transfer" }

        /// A debugging description that omits the amount.
        var debugDescription: String { description }

        /// A reflection view that omits the amount.
        var customMirror: Mirror { Mirror(self, children: [:]) }
    }

    /// The random values of one plan: the blinding seed, the salt, and the padding.
    ///
    /// Descriptions and reflection omit the values: with the public first nullifier, the blinding
    /// seed derives every output blinding and the private transaction blinding.
    struct Randomness: Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
        /// The proof's private blinding seed, below 2^248.
        let blindingSeed: Poseidon.Element
        /// The 16-byte salt of the notes.
        let salt: [UInt8]
        /// The blinding of each padding input, below 2^248.
        let paddingInputBlindings: [Poseidon.Element]
        /// The payload of each padding output, as long as a note.
        let paddingOutputData: [[UInt8]]

        /// A description that omits the random values.
        var description: String { "TransactPlan.Randomness" }

        /// A debugging description that omits the random values.
        var debugDescription: String { description }

        /// A reflection view that omits the random values.
        var customMirror: Mirror { Mirror(self, children: [:]) }

        /// Draws random values, as zolana's clients do: blindings are 31 random bytes, right-aligned.
        ///
        /// - Parameters:
        ///   - paddingInputs: The number of padding inputs.
        ///   - paddingOutputs: The number of padding outputs.
        ///   - generator: The source of randomness, such as `SystemRandomNumberGenerator`.
        /// - Returns: The random values.
        static func random(paddingInputs: Int, paddingOutputs: Int, using generator: inout some RandomNumberGenerator) -> Self {
            Self(
                blindingSeed: blinding(using: &generator),
                salt: bytes(count: SlotCipher.saltLength, using: &generator),
                paddingInputBlindings: (0..<paddingInputs).map { _ in blinding(using: &generator) },
                paddingOutputData: (0..<paddingOutputs).map { _ in
                    bytes(count: ConfidentialOutput.payloadLength, using: &generator)
                }
            )
        }

        /// Draws a blinding: 31 random bytes, right-aligned in a field element.
        ///
        /// - Parameter generator: The source of randomness.
        /// - Returns: The blinding, below 2^248 and so below r.
        private static func blinding(using generator: inout some RandomNumberGenerator) -> Poseidon.Element {
            var random = bytes(count: 31, using: &generator)
            defer { random.erase() }
            return PackedBytes.field(of: random)
        }

        /// Draws random bytes.
        ///
        /// - Parameters:
        ///   - count: The number of bytes.
        ///   - generator: The source of randomness.
        /// - Returns: The bytes.
        private static func bytes(count: Int, using generator: inout some RandomNumberGenerator) -> [UInt8] {
            (0..<count).map { _ in UInt8.random(in: .min ... .max, using: &generator) }
        }
    }

    /// One input slot: a spent UTXO, or padding.
    struct Input: Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
        /// The spent UTXO, or `nil` for padding.
        let utxo: UTXO?
        /// The position of the slot's tree among the declared input trees.
        let treeIndex: UInt8
        /// The slot's UTXO hash: the spent UTXO's, or the empty UTXO's for padding.
        let hash: Poseidon.Element
        /// The nullifier that the transact publishes for the slot.
        let nullifier: Poseidon.Element
        /// The slot's blinding: the spent UTXO's, or the padding's random blinding.
        let blinding: Poseidon.Element

        /// A description that omits the UTXO and the blinding.
        var description: String { "TransactPlan.Input" }

        /// A debugging description that omits the UTXO and the blinding.
        var debugDescription: String { description }

        /// A reflection view that omits the UTXO and the blinding.
        var customMirror: Mirror { Mirror(self, children: [:]) }
    }

    /// One output slot: a new UTXO, or padding.
    struct Output: Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
        /// The new UTXO, or `nil` for padding.
        let utxo: UTXO?
        /// The slot as the instruction publishes it.
        let published: TransactOutput
        /// The slot's blinding, which derives from the first nullifier and the blinding seed.
        let blinding: Poseidon.Element
        /// The owner of the new UTXO, or `nil` for padding.
        let owner: Recipient?

        /// A description that omits the UTXO, the blinding, and the owner.
        var description: String { "TransactPlan.Output" }

        /// A debugging description that omits the UTXO, the blinding, and the owner.
        var debugDescription: String { description }

        /// A reflection view that omits the UTXO, the blinding, and the owner.
        var customMirror: Mirror { Mirror(self, children: [:]) }
    }

    /// The validated slots of a plan before its random values.
    private struct Layout {
        /// The sender as an owner of outputs.
        let senderOwner: Recipient
        /// The spent UTXOs, in the caller's order.
        let utxos: [UTXO]
        /// The declared input trees, in first-use order.
        let inputTreeIDs: [UInt16]
        /// The owner and the amount of each real output, in slot order.
        let outputs: [(owner: Recipient, lamports: UInt64)]
        /// The view tag of the padding outputs.
        let paddingViewTag: [UInt8]
        /// The proof's shape.
        let shape: Shape

        /// The number of padding inputs.
        var paddingInputCount: Int { shape.inputs - utxos.count }

        /// The number of padding outputs.
        var paddingOutputCount: Int { shape.outputs - outputs.count }

        /// Validates a transact and lays out its slots.
        ///
        /// - Parameters:
        ///   - utxos: The spent UTXOs.
        ///   - sender: The sender.
        ///   - transfer: The transfer, if any.
        ///   - withdrawal: The withdrawal, if any.
        /// - Throws: A ``ValidationError`` if the plan can't be built,
        ///   ``Transactions/ValidationError/invalidAmount`` for a zero-lamport transfer or withdrawal,
        ///   or a ``Recipient/ValidationError`` if no key can sign for the sender's signing address.
        init(utxos: [UTXO], sender: ShieldedAccount, transfer: Transfer?, withdrawal: ExternalData.Withdrawal?) throws {
            guard !utxos.isEmpty else { throw ValidationError.noInputs }
            guard utxos.count <= TransactPlan.maximumInputs else { throw ValidationError.tooManyInputs }
            let senderOwner = try sender.recipient
            var inputTreeIDs = [UInt16]()
            for utxo in utxos {
                guard utxo.owner == senderOwner.owner else { throw ValidationError.foreignInput }
                guard utxo.mint == ConfidentialPlaintext.Asset.sol.mint else { throw ValidationError.unsupportedAsset }
                if !inputTreeIDs.contains(utxo.treeID) { inputTreeIDs.append(utxo.treeID) }
            }
            guard inputTreeIDs.count <= 2 else { throw ValidationError.tooManyInputTrees }
            guard transfer?.lamports != 0, withdrawal?.lamports != 0 else { throw Transactions.ValidationError.invalidAmount }
            guard transfer != nil || withdrawal != nil else { throw ValidationError.nothingToSend }
            let available = try Self.sum(utxos.map(\.amount))
            let spent = try Self.sum([transfer?.lamports ?? 0, withdrawal?.lamports ?? 0])
            guard available >= spent else { throw ValidationError.insufficientFunds }
            var outputs = [(owner: Recipient, lamports: UInt64)]()
            if let transfer { outputs.append((transfer.recipient, transfer.lamports)) }
            if available > spent { outputs.append((senderOwner, available - spent)) }
            guard let shape = Shape.fitting(inputs: utxos.count, outputs: outputs.count) else {
                preconditionFailure("A supported shape holds every allowed input and two outputs.")
            }
            if outputs.contains(where: { $0.owner.viewTag == senderOwner.viewTag }) {
                paddingViewTag = senderOwner.viewTag
            } else if let first = outputs.first {
                paddingViewTag = first.owner.viewTag
            } else {
                outputs.append((senderOwner, 0))
                paddingViewTag = senderOwner.viewTag
            }
            self.senderOwner = senderOwner
            self.utxos = utxos
            self.inputTreeIDs = inputTreeIDs
            self.outputs = outputs
            self.shape = shape
        }

        /// Adds amounts without overflow.
        ///
        /// - Parameter amounts: The amounts, in lamports.
        /// - Returns: Their sum.
        /// - Throws: ``ValidationError/amountOverflow`` if the sum exceeds a 64-bit integer.
        private static func sum(_ amounts: [UInt64]) throws -> UInt64 {
            try amounts.reduce(0) { total, amount in
                let (sum, overflow) = total.addingReportingOverflow(amount)
                guard !overflow else { throw ValidationError.amountOverflow }
                return sum
            }
        }
    }

    /// The most UTXOs that a plan spends, zolana's `MAX_SPEND_INPUTS`: the cheapest shape that holds
    /// them still fits one transaction, and the next wider one doesn't.
    private static let maximumInputs = 40

    /// The proof's shape.
    let shape: Shape

    /// The declared input trees, in first-use order.
    let inputTreeIDs: [UInt16]

    /// The ID of the tree that receives the outputs.
    let outputTreeID: UInt16

    /// The proof's private blinding seed, which the prover needs to derive the output blindings
    /// and the private transaction blinding.
    let blindingSeed: Poseidon.Element

    /// The input slots, padding last.
    let inputs: [Input]

    /// The output slots, padding last.
    let outputs: [Output]

    /// The withdrawal, if any.
    let withdrawal: ExternalData.Withdrawal?

    /// The fee payer, the sender.
    let payer: Address

    /// The public part of the transact that the proof commits to.
    let externalData: ExternalData

    /// The private transaction hash that the proof publishes.
    let privateTransactionHash: Poseidon.Element

    /// The nullifiers that the transact publishes, in input slot order.
    var nullifiers: [Poseidon.Element] { inputs.map(\.nullifier) }

    /// The UTXO hashes that the output tree appends, in output slot order.
    var commitments: [Poseidon.Element] { outputs.map(\.published.utxoHash) }

    /// The payloads of the output slots, in slot order.
    var payloads: [[UInt8]] { outputs.map(\.published.data) }

    /// A description that omits the amounts and the blindings.
    var description: String { "TransactPlan" }

    /// A debugging description that omits the amounts and the blindings.
    var debugDescription: String { description }

    /// A reflection view that omits the amounts and the blindings.
    var customMirror: Mirror { Mirror(self, children: [:]) }

    /// Plans a transact with random blindings, salt, and padding.
    ///
    /// - Parameters:
    ///   - utxos: The sender's SOL UTXOs to spend, in slot order.
    ///   - sender: The sender, who pays the fee.
    ///   - transfer: The transfer to another owner, if any.
    ///   - withdrawal: The withdrawal to a public account, if any.
    ///   - outputTreeID: The ID of the tree that receives the outputs.
    ///   - generator: The source of randomness, such as `SystemRandomNumberGenerator`.
    /// - Throws: A ``ValidationError`` if the plan can't be built,
    ///   ``Transactions/ValidationError/invalidAmount`` for a zero-lamport transfer or withdrawal, a
    ///   ``Recipient/ValidationError`` if no key can sign for the sender's signing address, or an
    ///   error from sealing the notes or deriving the accounts.
    init(
        spending utxos: [UTXO],
        sender: ShieldedAccount,
        transfer: Transfer?,
        withdrawal: ExternalData.Withdrawal?,
        outputTreeID: UInt16,
        using generator: inout some RandomNumberGenerator
    ) throws {
        let layout = try Layout(utxos: utxos, sender: sender, transfer: transfer, withdrawal: withdrawal)
        let randomness = Randomness.random(
            paddingInputs: layout.paddingInputCount, paddingOutputs: layout.paddingOutputCount, using: &generator
        )
        try self.init(layout: layout, sender: sender, withdrawal: withdrawal, outputTreeID: outputTreeID, randomness: randomness)
    }

    /// Plans a transact with given random values, such as a test vector's.
    ///
    /// - Parameters:
    ///   - utxos: The sender's SOL UTXOs to spend, in slot order.
    ///   - sender: The sender, who pays the fee.
    ///   - transfer: The transfer to another owner, if any.
    ///   - withdrawal: The withdrawal to a public account, if any.
    ///   - outputTreeID: The ID of the tree that receives the outputs.
    ///   - randomness: The random values, with one blinding per padding input and one payload per
    ///     padding output.
    /// - Throws: A ``ValidationError`` if the plan can't be built,
    ///   ``Transactions/ValidationError/invalidAmount`` for a zero-lamport transfer or withdrawal, a
    ///   ``Recipient/ValidationError`` if no key can sign for the sender's signing address, or an
    ///   error from sealing the notes or deriving the accounts.
    /// - Precondition: `randomness` holds as many padding values as the plan has padding slots, and
    ///   a 16-byte salt.
    init(
        spending utxos: [UTXO],
        sender: ShieldedAccount,
        transfer: Transfer?,
        withdrawal: ExternalData.Withdrawal?,
        outputTreeID: UInt16,
        randomness: Randomness
    ) throws {
        let layout = try Layout(utxos: utxos, sender: sender, transfer: transfer, withdrawal: withdrawal)
        try self.init(layout: layout, sender: sender, withdrawal: withdrawal, outputTreeID: outputTreeID, randomness: randomness)
    }

    /// Fills a validated layout with its random values, commitments, notes, and hashes.
    ///
    /// - Parameters:
    ///   - layout: The validated slots.
    ///   - sender: The sender.
    ///   - withdrawal: The withdrawal, if any.
    ///   - outputTreeID: The ID of the tree that receives the outputs.
    ///   - randomness: The random values.
    /// - Throws: An error from sealing the notes or deriving the accounts.
    /// - Precondition: `randomness` holds as many padding values as the layout has padding slots.
    private init(
        layout: Layout,
        sender: ShieldedAccount,
        withdrawal: ExternalData.Withdrawal?,
        outputTreeID: UInt16,
        randomness: Randomness
    ) throws {
        precondition(randomness.paddingInputBlindings.count == layout.paddingInputCount, "Each padding input needs a blinding.")
        precondition(randomness.paddingOutputData.count == layout.paddingOutputCount, "Each padding output needs a payload.")
        let paddingNullifierKey = try NullifierKey(secret: SymmetricKey(data: [UInt8](repeating: 0, count: 31)))
        let paddingTreeID = layout.inputTreeIDs[layout.inputTreeIDs.count - 1]
        let spent = layout.utxos.map { utxo in
            let hash = utxo.hash
            return Input(
                utxo: utxo, treeIndex: Self.index(of: utxo.treeID, in: layout.inputTreeIDs), hash: hash,
                nullifier: sender.nullifierKey.nullifier(utxoHash: hash, blinding: utxo.blinding), blinding: utxo.blinding
            )
        }
        let padding = randomness.paddingInputBlindings.map { blinding in
            let hash = UTXO.dummyHash(treeID: paddingTreeID, blinding: blinding)
            return Input(
                utxo: nil, treeIndex: Self.index(of: paddingTreeID, in: layout.inputTreeIDs), hash: hash,
                nullifier: paddingNullifierKey.nullifier(utxoHash: hash, blinding: blinding), blinding: blinding
            )
        }
        let inputs = spent + padding
        let firstNullifier = inputs[0].nullifier
        let outputBlindingSeed = TransactBlinding.outputBlindingSeed(firstNullifier: firstNullifier, blindingSeed: randomness.blindingSeed)
        let transactionViewingKey = try TransactionViewingKey.derive(viewingKey: sender.viewingKey, firstNullifier: firstNullifier)
        let outputs = try (0..<layout.shape.outputs).map { slot in
            let blinding = TransactBlinding.outputBlinding(
                firstNullifier: firstNullifier, outputBlindingSeed: outputBlindingSeed, index: UInt32(slot)
            )
            guard slot < layout.outputs.count else {
                return Output(utxo: nil, published: TransactOutput(
                    utxoHash: UTXO.dummyHash(treeID: outputTreeID, blinding: blinding), ownerTag: .inline(layout.paddingViewTag),
                    data: randomness.paddingOutputData[slot - layout.outputs.count]
                ), blinding: blinding, owner: nil)
            }
            let (owner, lamports) = layout.outputs[slot]
            let utxo = UTXO(
                owner: owner.owner, mint: ConfidentialPlaintext.Asset.sol.mint, amount: lamports, blinding: blinding, treeID: outputTreeID
            )
            let note = try ConfidentialOutput.seal(
                ConfidentialPlaintext(asset: .sol, amount: lamports, blinding: blinding), for: owner.viewingPublicKey,
                transactionViewingKey: transactionViewingKey, salt: randomness.salt, slot: UInt32(slot)
            )
            let ownerTag: TransactOutput.OwnerTag = owner.viewTag == layout.senderOwner.viewTag ? .payer : .inline(owner.viewTag)
            return Output(utxo: utxo, published: TransactOutput(
                utxoHash: utxo.hash, ownerTag: ownerTag, data: note.encoded
            ), blinding: blinding, owner: owner)
        }
        shape = layout.shape
        inputTreeIDs = layout.inputTreeIDs
        self.outputTreeID = outputTreeID
        blindingSeed = randomness.blindingSeed
        self.inputs = inputs
        self.outputs = outputs
        self.withdrawal = withdrawal
        payer = sender.signingAddress
        externalData = try ExternalData(
            transactionViewingPublicKey: transactionViewingKey.publicKey, salt: randomness.salt, withdrawal: withdrawal,
            outputs: outputs.map(\.published), payer: sender.signingAddress
        )
        privateTransactionHash = PrivateTransactionHash.hash(
            inputs: inputs.map { $0.utxo == nil ? .zero : $0.hash },
            outputs: outputs.map { $0.utxo == nil ? .zero : $0.published.utxoHash },
            blinding: TransactBlinding.privateTransactionBlinding(firstNullifier: firstNullifier, blindingSeed: randomness.blindingSeed)
        )
    }

    /// Finds a tree's position among the declared input trees.
    ///
    /// - Parameters:
    ///   - treeID: A declared tree's ID.
    ///   - treeIDs: The declared trees, at most two.
    /// - Returns: The tree's position.
    /// - Precondition: `treeIDs` contains `treeID`.
    private static func index(of treeID: UInt16, in treeIDs: [UInt16]) -> UInt8 {
        guard let index = treeIDs.firstIndex(of: treeID) else { preconditionFailure("Every input's tree is declared.") }
        return UInt8(index)
    }
}
