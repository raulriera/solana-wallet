import Encoding

/// The JSON body of a transfer proof request on the prover's indexed route.
///
/// Field elements are `0x` and lowercase hexadecimal digits without leading zeros, `0x0` for zero; counts,
/// tree IDs, and slots in the lookup are JSON numbers; commitments and nullifiers in the lookup are base 58.
struct TransferProofBody: Encodable, Sendable {
    /// The circuit of a default-ring confidential transfer.
    private static let circuitType = "transfer-confidential"

    /// The circuit's name.
    let circuitType = Self.circuitType
    /// The value of the `trees` field.
    let trees: [Tree]
    /// The value of the `inputs` field.
    let inputs: [Input]
    /// The value of the `publicInputs` field.
    let publicInputs: [String]
    /// The value of the `minContextSlot` field.
    let minContextSlot: UInt64?
    /// The value of the `prepared` field.
    let prepared: Prepared

    /// Creates the body of a request.
    ///
    /// - Parameter request: The validated request.
    init(_ request: TransferProofRequest) {
        trees = request.trees.map { Tree(tree: $0.address, id: $0.id) }
        inputs = request.inputs.map {
            Input(treeSlot: $0.treeSlot, commitment: $0.commitment.map(Base58.encode),
                  nullifier: $0.nullifier.map(Base58.encode))
        }
        publicInputs = request.publicInputs.map(FieldHex.encode)
        minContextSlot = request.minContextSlot
        prepared = Prepared(request.witness)
    }

    /// Encodes the body, omitting a missing minimum slot and writing `null` for a missing lookup value.
    ///
    /// - Parameter encoder: The encoder that receives the body.
    /// - Throws: An encoding error, which valid values don't produce.
    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(circuitType, forKey: .circuitType)
        try container.encode(trees, forKey: .trees)
        try container.encode(inputs, forKey: .inputs)
        try container.encode(publicInputs, forKey: .publicInputs)
        try container.encodeIfPresent(minContextSlot, forKey: .minContextSlot)
        try container.encode(prepared, forKey: .prepared)
    }

    /// The body's top-level fields.
    private enum CodingKeys: String, CodingKey {
        case circuitType, trees, inputs, publicInputs, minContextSlot, prepared
    }

    /// A tree's address and ID.
    struct Tree: Encodable, Sendable {
        /// The value of the `tree` field.
        let tree: String
        /// The value of the `id` field.
        let id: UInt16
    }

    /// One input slot's lookup; absent values are `null`.
    struct Input: Encodable, Sendable {
        /// The value of the `treeSlot` field.
        let treeSlot: UInt8
        /// The value of the `commitment` field.
        let commitment: String?
        /// The value of the `nullifier` field.
        let nullifier: String?

        /// Encodes the lookup with explicit `null` values.
        ///
        /// - Parameter encoder: The encoder that receives the lookup.
        /// - Throws: An encoding error, which valid values don't produce.
        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(treeSlot, forKey: .treeSlot)
            try container.encode(commitment, forKey: .commitment)
            try container.encode(nullifier, forKey: .nullifier)
        }

        /// The lookup's fields.
        private enum CodingKeys: String, CodingKey {
            case treeSlot, commitment, nullifier
        }
    }

    /// The witness, as zolana's `prepared` object.
    struct Prepared: Encodable, Sendable {
        /// The circuit's name.
        let circuitType = TransferProofBody.circuitType
        /// The value of the `nInputs` field.
        let nInputs: Int
        /// The value of the `nOutputs` field.
        let nOutputs: Int
        /// The value of the `inputs` field.
        let inputs: [PreparedInput]
        /// The value of the `outputs` field.
        let outputs: [PreparedOutput]
        /// The value of the `outputTreeId` field.
        let outputTreeId: String
        /// The value of the `blindingSeed` field.
        let blindingSeed: String
        /// The value of the `externalDataHash` field.
        let externalDataHash: String
        /// The value of the `privateTxHash` field.
        let privateTxHash: String
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

        /// Creates the witness's text.
        ///
        /// - Parameter witness: The validated witness.
        init(_ witness: TransferProofRequest.Witness) {
            nInputs = witness.inputs.count
            nOutputs = witness.outputs.count
            inputs = witness.inputs.map(PreparedInput.init)
            outputs = witness.outputs.map(PreparedOutput.init)
            outputTreeId = FieldHex.encode(integer: UInt64(witness.outputTreeID))
            blindingSeed = FieldHex.encode(witness.blindingSeed)
            externalDataHash = FieldHex.encode(witness.externalDataHash)
            privateTxHash = FieldHex.encode(witness.privateTransactionHash)
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
        }
    }

    /// One input slot of the witness.
    struct PreparedInput: Encodable, Sendable {
        /// The value of the `utxo` field.
        let utxo: PreparedUTXO
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

        /// Creates an input slot's text.
        ///
        /// - Parameter input: The validated input slot.
        init(_ input: TransferProofRequest.WitnessInput) {
            utxo = PreparedUTXO(input.utxo)
            isDummy = FieldHex.encode(integer: input.isDummy ? 1 : 0)
            treeSlot = FieldHex.encode(integer: UInt64(input.treeSlot))
            nullifier = FieldHex.encode(input.nullifier)
            ownerPkHash = FieldHex.encode(input.ownerPublicKeyHash)
            nullifierSecret = FieldHex.encode(input.nullifierSecret)
        }
    }

    /// One output slot of the witness.
    struct PreparedOutput: Encodable, Sendable {
        /// The value of the `utxo` field.
        let utxo: PreparedUTXO
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
            utxo = PreparedUTXO(output.utxo)
            isDummy = FieldHex.encode(integer: output.isDummy ? 1 : 0)
            hash = FieldHex.encode(output.hash)
            ownerPkHash = FieldHex.encode(output.ownerPublicKeyHash)
            nullifierPk = FieldHex.encode(output.nullifierPublicKey)
        }
    }

    /// A UTXO's eight field elements.
    struct PreparedUTXO: Encodable, Sendable {
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
