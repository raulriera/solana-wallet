/// The JSON body of a transfer proof request on the prover's complete route, zolana's flat
/// `TransferParametersJSON`.
///
/// Every field element, index, and tree ID is `0x` and lowercase hexadecimal digits without leading zeros, `0x0`
/// for zero; the prover reads text without `0x` as hexadecimal too, so decimal text would be misread. Only the
/// circuit type and the slot counts aren't hexadecimal. The five tree slots follow the declared trees with zeros.
struct TransferProofBody: Encodable, Sendable {
    /// The circuit's name.
    let circuitType = "transfer-confidential"
    /// The value of the `nInputs` field.
    let nInputs: Int
    /// The value of the `nOutputs` field.
    let nOutputs: Int
    /// The value of the `inputs` field.
    let inputs: [Input]
    /// The value of the `outputs` field.
    let outputs: [Output]
    /// The value of the `treeSlots` field.
    let treeSlots: [TreeSlot]
    /// The value of the `outputTreeId` field.
    let outputTreeId: String
    /// The value of the `externalDataHash` field.
    let externalDataHash: String
    /// The value of the `privateTxHash` field.
    let privateTxHash: String
    /// The value of the `blindingSeed` field.
    let blindingSeed: String
    /// The value of the `publicAssets` field.
    let publicAssets: [String]
    /// The value of the `publicAmounts` field.
    let publicAmounts: [String]
    /// The value of the `ringProgramId` field.
    let ringProgramId: String
    /// The value of the `signerPkHashes` field.
    let signerPkHashes: [String]
    /// The value of the `inputFlags` field.
    let inputFlags: String
    /// The value of the `publishedOutputOwnerPkHashes` field.
    let publishedOutputOwnerPkHashes: [String]
    /// The value of the `cacheTreeId` field.
    let cacheTreeId: String
    /// The value of the `cacheReadHashChain` field.
    let cacheReadHashChain: String
    /// The value of the `cacheReadHashes` field.
    let cacheReadHashes: [String]
    /// The value of the `cacheIsCached` field.
    let cacheIsCached: [String]
    /// The value of the `cacheReadIndex` field.
    let cacheReadIndex: [String]
    /// The value of the `publicInputHash` field.
    let publicInputHash: String

    /// Creates the body of a request.
    ///
    /// - Parameter request: The validated request.
    init(_ request: TransferProofRequest) {
        let witness = request.witness
        let unused = TreeSlot(id: "0x0", utxoRoot: "0x0", nullifierRoot: "0x0")
        nInputs = witness.inputs.count
        nOutputs = witness.outputs.count
        inputs = witness.inputs.map(Input.init)
        outputs = witness.outputs.map(Output.init)
        treeSlots = request.treeSlots.map(TreeSlot.init)
            + Array(repeating: unused, count: TransferProofRequest.treeSlotCount - request.treeSlots.count)
        outputTreeId = FieldHex.encode(integer: UInt64(witness.outputTreeID))
        externalDataHash = FieldHex.encode(witness.externalDataHash)
        privateTxHash = FieldHex.encode(witness.privateTransactionHash)
        blindingSeed = FieldHex.encode(witness.blindingSeed)
        publicAssets = witness.publicAssets.map(FieldHex.encode)
        publicAmounts = witness.publicAmounts.map(FieldHex.encode)
        ringProgramId = FieldHex.encode(witness.ringProgramID)
        signerPkHashes = witness.signerPublicKeyHashes.map(FieldHex.encode)
        inputFlags = FieldHex.encode(witness.inputFlags)
        publishedOutputOwnerPkHashes = witness.publishedOutputOwnerPublicKeyHashes.map(FieldHex.encode)
        cacheTreeId = FieldHex.encode(witness.cacheTreeID)
        cacheReadHashChain = FieldHex.encode(witness.cacheReadHashChain)
        cacheReadHashes = witness.cacheReadHashes.map(FieldHex.encode)
        cacheIsCached = witness.cacheIsCached.map { FieldHex.encode(integer: $0 ? 1 : 0) }
        cacheReadIndex = witness.cacheReadIndexes.map { FieldHex.encode(integer: $0) }
        publicInputHash = FieldHex.encode(request.publicInputHash)
    }

    /// A tree slot's ID and roots.
    struct TreeSlot: Encodable, Sendable {
        /// The value of the `id` field.
        let id: String
        /// The value of the `utxoRoot` field.
        let utxoRoot: String
        /// The value of the `nullifierRoot` field.
        let nullifierRoot: String
    }

    /// One input slot, with its Merkle and non-inclusion paths.
    struct Input: Encodable, Sendable {
        /// The value of the `utxo` field.
        let utxo: UTXO
        /// The value of the `isDummy` field.
        let isDummy: String
        /// The value of the `treeSlot` field.
        let treeSlot: String
        /// The value of the `nullifier` field.
        let nullifier: String
        /// The value of the `ownerPkHash` field.
        let ownerPkHash: String
        /// The value of the `nullifierSecret` field.
        let nullifierSecret: String
        /// The value of the `statePathElements` field: 32 siblings, zero without an inclusion proof.
        let statePathElements: [String]
        /// The value of the `statePathIndex` field.
        let statePathIndex: String
        /// The value of the `nullifierLowValue` field.
        let nullifierLowValue: String
        /// The value of the `nullifierNextValue` field.
        let nullifierNextValue: String
        /// The value of the `nullifierLowPathElements` field: 40 siblings.
        let nullifierLowPathElements: [String]
        /// The value of the `nullifierLowPathIndex` field.
        let nullifierLowPathIndex: String

        /// Creates an input slot's text.
        ///
        /// - Parameter input: The validated input slot.
        init(_ input: TransferProofRequest.WitnessInput) {
            utxo = UTXO(input.utxo)
            isDummy = FieldHex.encode(integer: input.isDummy ? 1 : 0)
            treeSlot = FieldHex.encode(integer: UInt64(input.treeSlot))
            nullifier = FieldHex.encode(input.nullifier)
            ownerPkHash = FieldHex.encode(input.ownerPublicKeyHash)
            nullifierSecret = FieldHex.encode(input.nullifierSecret)
            statePathElements = input.inclusionProof?.path.map(FieldHex.encode)
                ?? Array(repeating: FieldHex.encode(integer: 0), count: MerkleProof.height)
            statePathIndex = FieldHex.encode(integer: input.inclusionProof?.leafIndex ?? 0)
            nullifierLowValue = FieldHex.encode(input.nonInclusionProof.lowElement)
            nullifierNextValue = FieldHex.encode(input.nonInclusionProof.highElement)
            nullifierLowPathElements = input.nonInclusionProof.path.map(FieldHex.encode)
            nullifierLowPathIndex = FieldHex.encode(integer: input.nonInclusionProof.lowElementIndex)
        }
    }

    /// One output slot.
    struct Output: Encodable, Sendable {
        /// The value of the `utxo` field.
        let utxo: UTXO
        /// The value of the `isDummy` field.
        let isDummy: String
        /// The value of the `hash` field.
        let hash: String
        /// The value of the `ownerPkHash` field.
        let ownerPkHash: String
        /// The value of the `nullifierPk` field.
        let nullifierPk: String

        /// Creates an output slot's text.
        ///
        /// - Parameter output: The validated output slot.
        init(_ output: TransferProofRequest.WitnessOutput) {
            utxo = UTXO(output.utxo)
            isDummy = FieldHex.encode(integer: output.isDummy ? 1 : 0)
            hash = FieldHex.encode(output.hash)
            ownerPkHash = FieldHex.encode(output.ownerPublicKeyHash)
            nullifierPk = FieldHex.encode(output.nullifierPublicKey)
        }
    }

    /// A UTXO's eight field elements.
    struct UTXO: Encodable, Sendable {
        /// The value of the `domain` field.
        let domain: String
        /// The value of the `owner` field.
        let owner: String
        /// The value of the `asset` field.
        let asset: String
        /// The value of the `amount` field.
        let amount: String
        /// The value of the `blinding` field.
        let blinding: String
        /// The value of the `dataHash` field.
        let dataHash: String
        /// The value of the `ringDataHash` field.
        let ringDataHash: String
        /// The value of the `ringProgramId` field.
        let ringProgramId: String

        /// Creates a UTXO's text.
        ///
        /// - Parameter utxo: The validated UTXO.
        init(_ utxo: TransferProofRequest.UTXO) {
            domain = FieldHex.encode(utxo.domain)
            owner = FieldHex.encode(utxo.owner)
            asset = FieldHex.encode(utxo.asset)
            amount = FieldHex.encode(utxo.amount)
            blinding = FieldHex.encode(utxo.blinding)
            dataHash = FieldHex.encode(utxo.dataHash)
            ringDataHash = FieldHex.encode(utxo.ringDataHash)
            ringProgramId = FieldHex.encode(utxo.ringProgramID)
        }
    }
}

extension TransferProofBody.TreeSlot {
    /// Creates a declared tree slot's text.
    ///
    /// - Parameter slot: The validated tree slot.
    init(_ slot: TransferProofRequest.TreeSlot) {
        self.init(id: FieldHex.encode(integer: UInt64(slot.id)), utxoRoot: FieldHex.encode(slot.utxoRoot),
                  nullifierRoot: FieldHex.encode(slot.nullifierRoot))
    }
}
