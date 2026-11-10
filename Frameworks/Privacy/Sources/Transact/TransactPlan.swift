import CryptoKit
import ModularArithmetic
import Transactions

/// A default-ring SOL transact before its proof: the sender spends UTXOs into a transfer, a public
/// withdrawal, or both, and keeps the change.
struct TransactPlan: Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    /// A transact that the plan can't build.
    enum ValidationError: Error, Equatable {
        case noInputs
        case tooManyInputs
        case nothingToSend
        /// An input isn't owned by the sender.
        case foreignInput
        /// An input isn't SOL.
        case unsupportedAsset
        /// The inputs come from more than two trees.
        case tooManyInputTrees
        case insufficientFunds
        case amountOverflow
        case invalidTreeContextCount
        /// A resolved tree isn't the declared input tree at its position.
        case mismatchedTree
        case foreignNullifierKey
        /// The proof's proving key isn't the one for the plan's shape.
        case unexpectedProvingKey
        case rootIndexOutOfRange
        /// A root isn't a canonical field element.
        case invalidRoot
        /// The prover's public input hash isn't the plan's statement with the resolved roots.
        case mismatchedPublicInputHash
    }

    /// A transfer of SOL to another owner's shielded address.
    struct Transfer: Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
        let recipient: Recipient
        let lamports: UInt64

        var description: String { "TransactPlan.Transfer" }

        var debugDescription: String { description }

        var customMirror: Mirror { Mirror(self, children: [:]) }
    }

    /// The random values of one plan: the blinding seed, the salt, and the padding.
    struct Randomness: Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
        /// The proof's private blinding seed, below 2^248.
        let blindingSeed: Poseidon.Element
        /// The 16-byte salt of the notes.
        let salt: [UInt8]
        /// The blinding of each padding input, below 2^248.
        let paddingInputBlindings: [Poseidon.Element]
        /// The payload of each padding output, as long as a note.
        let paddingOutputData: [[UInt8]]

        var description: String { "TransactPlan.Randomness" }

        var debugDescription: String { description }

        var customMirror: Mirror { Mirror(self, children: [:]) }

        /// Draws random values for a plan.
        ///
        /// - Parameters:
        ///   - paddingInputs: The number of padding inputs.
        ///   - paddingOutputs: The number of padding outputs.
        ///   - generator: The source of randomness.
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

        /// Draws a blinding from 31 random bytes.
        ///
        /// - Parameter generator: The source of randomness.
        /// - Returns: The blinding, below 2^248.
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
        let nullifier: Poseidon.Element
        let blinding: Poseidon.Element

        var description: String { "TransactPlan.Input" }

        var debugDescription: String { description }

        var customMirror: Mirror { Mirror(self, children: [:]) }
    }

    /// One output slot: a new UTXO, or padding.
    struct Output: Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
        /// The new UTXO, or `nil` for padding.
        let utxo: UTXO?
        /// The slot as the instruction publishes it.
        let published: TransactOutput
        let blinding: Poseidon.Element
        /// The owner of the new UTXO, or `nil` for padding.
        let owner: Recipient?

        var description: String { "TransactPlan.Output" }

        var debugDescription: String { description }

        var customMirror: Mirror { Mirror(self, children: [:]) }
    }

    /// The validated slots of a plan before its random values.
    private struct Layout {
        let senderOwner: Recipient
        let utxos: [UTXO]
        /// The asset that the transact spends: the withdrawal's, or SOL without one.
        let asset: ConfidentialPlaintext.Asset
        /// The declared input trees, in first-use order.
        let inputTreeIDs: [UInt16]
        /// The owner and the amount of each real output, in slot order.
        let outputs: [(owner: Recipient, lamports: UInt64)]
        let paddingViewTag: [UInt8]
        let shape: Shape

        var paddingInputCount: Int { shape.inputs - utxos.count }

        var paddingOutputCount: Int { shape.outputs - outputs.count }

        /// Creates a layout after validating a transact.
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
            let asset = withdrawal?.asset ?? .sol
            var inputTreeIDs: [UInt16] = []
            for utxo in utxos {
                guard utxo.owner == senderOwner.owner else { throw ValidationError.foreignInput }
                guard utxo.mint == asset.mint else { throw ValidationError.unsupportedAsset }
                if !inputTreeIDs.contains(utxo.treeID) { inputTreeIDs.append(utxo.treeID) }
            }
            guard inputTreeIDs.count <= TransactPlan.maximumInputTrees else { throw ValidationError.tooManyInputTrees }
            guard transfer?.lamports != 0, withdrawal?.amount != 0 else { throw Transactions.ValidationError.invalidAmount }
            guard transfer != nil || withdrawal != nil else { throw ValidationError.nothingToSend }
            let available = try Self.sum(utxos.map(\.amount))
            let spent = try Self.sum([transfer?.lamports ?? 0, withdrawal?.amount ?? 0])
            guard available >= spent else { throw ValidationError.insufficientFunds }
            var outputs: [(owner: Recipient, lamports: UInt64)] = []
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
            self.asset = asset
            self.inputTreeIDs = inputTreeIDs
            self.outputs = outputs
            self.shape = shape
        }

        /// Returns the owner tag of a view tag: a reference to the payer for the sender's view tag, else the
        /// tag inline.
        ///
        /// - Parameter viewTag: The output's view tag.
        /// - Returns: The output's owner tag.
        func ownerTag(for viewTag: [UInt8]) -> TransactOutput.OwnerTag {
            viewTag == senderOwner.viewTag ? .payer : .inline(viewTag)
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

    /// The most notes that one transact spends.
    static let maximumInputs = 40

    /// The most trees that one transact spends notes from.
    static let maximumInputTrees = 2

    /// Returns the trees that a transact writes, each of which charges its fee once.
    ///
    /// - Parameters:
    ///   - inputs: The IDs of the trees whose notes the transact spends.
    ///   - output: The ID of the tree that receives the outputs.
    /// - Returns: The input trees and the output tree.
    static func writtenTreeIDs(inputs: some Sequence<UInt16>, output: UInt16) -> Set<UInt16> {
        Set(inputs).union([output])
    }

    let shape: Shape

    /// The declared input trees, in first-use order.
    let inputTreeIDs: [UInt16]

    let outputTreeID: UInt16

    let blindingSeed: Poseidon.Element

    /// The input slots, padding last.
    let inputs: [Input]

    /// The output slots, padding last.
    let outputs: [Output]

    let withdrawal: ExternalData.Withdrawal?

    /// The fee payer, which is the sender.
    let payer: Address

    let externalData: ExternalData

    let privateTransactionHash: Poseidon.Element

    /// The nullifiers that the transact publishes, in input slot order.
    var nullifiers: [Poseidon.Element] { inputs.map(\.nullifier) }

    /// The UTXO hashes of the output slots, in slot order.
    var commitments: [Poseidon.Element] { outputs.map(\.published.utxoHash) }

    var payloads: [[UInt8]] { outputs.map(\.published.data) }

    var description: String { "TransactPlan" }

    var debugDescription: String { description }

    var customMirror: Mirror { Mirror(self, children: [:]) }

    /// Creates a plan with random blindings, salt, and padding.
    ///
    /// - Parameters:
    ///   - utxos: The sender's SOL UTXOs to spend, in slot order.
    ///   - sender: The sender, who pays the fee.
    ///   - transfer: The transfer to another owner, if any.
    ///   - withdrawal: The withdrawal to a public account, if any.
    ///   - outputTreeID: The ID of the tree that receives the outputs.
    ///   - generator: The source of randomness.
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

    /// Creates a plan with the given random values.
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

    /// Creates a plan from a validated layout and its random values.
    ///
    /// - Parameters:
    ///   - layout: The validated slots.
    ///   - sender: The sender.
    ///   - withdrawal: The withdrawal, if any.
    ///   - outputTreeID: The ID of the tree that receives the outputs.
    ///   - randomness: The random values.
    /// - Throws: An error from sealing the notes or deriving the accounts.
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
                    utxoHash: UTXO.dummyHash(treeID: outputTreeID, blinding: blinding), ownerTag: layout.ownerTag(for: layout.paddingViewTag),
                    data: randomness.paddingOutputData[slot - layout.outputs.count]
                ), blinding: blinding, owner: nil)
            }
            let (owner, lamports) = layout.outputs[slot]
            let utxo = UTXO(
                owner: owner.owner, mint: layout.asset.mint, amount: lamports, blinding: blinding, treeID: outputTreeID
            )
            let note = try ConfidentialOutput.seal(
                ConfidentialPlaintext(asset: layout.asset, amount: lamports, blinding: blinding), for: owner.viewingPublicKey,
                transactionViewingKey: transactionViewingKey, salt: randomness.salt, slot: UInt32(slot)
            )
            return Output(utxo: utxo, published: TransactOutput(
                utxoHash: utxo.hash, ownerTag: layout.ownerTag(for: owner.viewTag), data: note.encoded
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
    ///   - treeIDs: The declared trees.
    /// - Returns: The tree's position.
    private static func index(of treeID: UInt16, in treeIDs: [UInt16]) -> UInt8 {
        guard let index = treeIDs.firstIndex(of: treeID) else { preconditionFailure("Every input's tree is declared.") }
        return UInt8(index)
    }
}
