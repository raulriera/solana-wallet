import Encoding

/// The JSON body of an indexed transfer proof request.
struct IndexedTransferProofBody: Encodable, Sendable {
    let circuitType = "transfer-confidential"
    let prepared: Prepared
    let trees: [Tree]
    let inputs: [Input]
    let publicInputs: [String]

    /// Creates the body of a request.
    ///
    /// - Parameter request: The validated request.
    init(_ request: IndexedTransferProofRequest) {
        prepared = Prepared(request)
        trees = request.trees.map { Tree(tree: Base58.encode($0.address), id: $0.id) }
        inputs = request.inputs.map { Input(treeSlot: $0.treeSlot, commitment: $0.commitment.map(Base58.encode)) }
        publicInputs = request.publicInputs.map(FieldHex.encode)
    }

    /// The witness without tree slots, paths, a public input hash, or read cache entries.
    struct Prepared: Encodable, Sendable {
        let circuitType = "transfer-confidential"
        let nInputs: Int
        let nOutputs: Int
        let inputs: [PreparedInput]
        let outputs: [Output]
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
        let cacheTreeId = "0x0"
        let cacheReadHashChain: String
        let cacheReadHashes: [String] = []
        let cacheIsCached: [String] = []
        let cacheReadIndex: [String] = []

        /// Creates the witness text of a request.
        ///
        /// - Parameter request: The validated request.
        init(_ request: IndexedTransferProofRequest) {
            nInputs = request.inputs.count
            nOutputs = request.outputs.count
            inputs = request.inputs.map(PreparedInput.init)
            outputs = request.outputs.map(Output.init)
            outputTreeId = FieldHex.encode(integer: UInt64(request.outputTreeID))
            externalDataHash = FieldHex.encode(request.externalDataHash)
            privateTxHash = FieldHex.encode(request.privateTransactionHash)
            blindingSeed = FieldHex.encode(request.blindingSeed)
            publicAssets = request.publicAssets.map(FieldHex.encode)
            publicAmounts = request.publicAmounts.map(FieldHex.encode)
            ringProgramId = FieldHex.encode(request.ringProgramID)
            signerPkHashes = request.signerPublicKeyHashes.map(FieldHex.encode)
            inputFlags = FieldHex.encode(request.inputFlags)
            publishedOutputOwnerPkHashes = request.publishedOutputOwnerPublicKeyHashes.map(FieldHex.encode)
            cacheReadHashChain = FieldHex.encode(request.cacheReadHashChain)
        }
    }

    /// One input slot without its paths.
    struct PreparedInput: Encodable, Sendable {
        let utxo: UTXO
        let isDummy: String
        let treeSlot: String
        let nullifier: String
        let ownerPkHash: String
        let nullifierSecret: String

        /// Creates an input slot's text.
        ///
        /// - Parameter input: The validated input slot.
        init(_ input: IndexedTransferProofRequest.Input) {
            utxo = UTXO(input.utxo)
            isDummy = FieldHex.encode(integer: input.isDummy ? 1 : 0)
            treeSlot = FieldHex.encode(integer: UInt64(input.treeSlot))
            nullifier = FieldHex.encode(input.nullifier)
            ownerPkHash = FieldHex.encode(input.ownerPublicKeyHash)
            nullifierSecret = FieldHex.encode(input.nullifierSecret)
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
        init(_ output: IndexedTransferProofRequest.Output) {
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
        init(_ utxo: IndexedTransferProofRequest.UTXO) {
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

    /// A tree's base-58 address and ID.
    struct Tree: Encodable, Sendable {
        let tree: String
        let id: UInt16
    }

    /// An input's tree slot and the base-58 commitment that the prover reads its proofs for.
    struct Input: Encodable, Sendable {
        let treeSlot: UInt8
        /// The commitment, or `nil` to send `null` for padding.
        let commitment: String?

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(treeSlot, forKey: .treeSlot)
            try container.encode(commitment, forKey: .commitment)
        }

        private enum CodingKeys: String, CodingKey {
            case treeSlot, commitment
        }
    }
}
