/// The JSON body of a transfer proof request on the prover's complete route, zolana's flat
/// `TransferParametersJSON`.
///
/// Every field element, index, and tree ID is `0x` and lowercase hexadecimal digits without leading zeros, `0x0`
/// for zero; the prover reads text without `0x` as hexadecimal too, so decimal text would be misread. Only the
/// circuit type and the slot counts aren't hexadecimal. The five tree slots follow the declared trees with zeros.
struct TransferProofBody: Encodable, Sendable {
    /// The circuit's name.
    let circuitType = "transfer-confidential"
    let nInputs: Int
    let nOutputs: Int
    let inputs: [Input]
    let outputs: [Output]
    let treeSlots: [TreeSlot]
    let outputTreeId: String
    let externalDataHash: String
    let privateTxHash: String
    let blindingSeed: String
    let publicAssets: [String]
    let publicAmounts: [String]
    let ringProgramId: String
    let signerPkHashes: [String]
    let inputFlags: String
    let publishedOutputOwnerPkHashes: [String]
    let cacheTreeId: String
    let cacheReadHashChain: String
    let cacheReadHashes: [String]
    let cacheIsCached: [String]
    let cacheReadIndex: [String]
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
        let id: String
        let utxoRoot: String
        let nullifierRoot: String
    }

    /// One input slot, with its Merkle and non-inclusion paths.
    struct Input: Encodable, Sendable {
        let utxo: UTXO
        let isDummy: String
        let treeSlot: String
        let nullifier: String
        let ownerPkHash: String
        let nullifierSecret: String
        /// The value of the `statePathElements` field: 32 siblings, zero without an inclusion proof.
        let statePathElements: [String]
        let statePathIndex: String
        let nullifierLowValue: String
        let nullifierNextValue: String
        /// The value of the `nullifierLowPathElements` field: 40 siblings.
        let nullifierLowPathElements: [String]
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
        let utxo: UTXO
        let isDummy: String
        let hash: String
        let ownerPkHash: String
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
        let domain: String
        let owner: String
        let asset: String
        let amount: String
        let blinding: String
        let dataHash: String
        let ringDataHash: String
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
