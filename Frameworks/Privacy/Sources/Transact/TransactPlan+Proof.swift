import ModularArithmetic
import RPC
import Transactions

extension TransactPlan {
    /// Creates the request for the plan's proof.
    ///
    /// - Parameter nullifierKey: The sender's nullifier key.
    /// - Returns: The request.
    /// - Throws: ``ValidationError/foreignNullifierKey`` if the key doesn't derive the spent inputs' nullifiers, a
    ///   ``Transactions/ValidationError`` if a tree account's derivation fails, or a
    ///   ``RPC/IndexedTransferProofRequest/ValidationError`` if a value is invalid.
    func proofRequest(nullifierKey: NullifierKey) throws -> IndexedTransferProofRequest {
        try check(nullifierKey)
        return try proofRequest(nullifierKey: nullifierKey, statement: publicInputs)
    }

    /// Checks the prover's response against the plan and converts its proof for the instruction.
    ///
    /// - Parameter response: The prover's response.
    /// - Returns: The proof.
    /// - Throws: ``ValidationError/unexpectedProvingKey`` for another proving key,
    ///   ``ProofPoint/ValidationError/invalidCoordinate`` for a coordinate at or above the base
    ///   field's modulus, or ``TransactProof/ValidationError/invalidLength`` if `b` doesn't have 128
    ///   bytes.
    func proof(from response: TransferProof) throws -> TransactProof {
        guard response.provingKeyDigest == shape.provingKeyDigest else { throw ValidationError.unexpectedProvingKey }
        return try TransactProof(
            a: ProofPoint.compressed(x: response.a.x, y: response.a.y, negated: true), b: response.b,
            c: ProofPoint.compressed(x: response.c.x, y: response.c.y)
        )
    }

    /// Proves the plan and creates its transact instruction.
    ///
    /// - Parameters:
    ///   - nullifierKey: The sender's nullifier key.
    ///   - prover: The prover.
    /// - Returns: The transact instruction.
    /// - Throws: An error from ``proofRequest(nullifierKey:)``, the prover, ``treeContexts(from:statement:)``,
    ///   ``proof(from:)``, or ``instruction(proof:treeContexts:)``.
    @concurrent
    func instruction(nullifierKey: NullifierKey, prover: some ProofProviding) async throws -> Instruction {
        try check(nullifierKey)
        let statement = publicInputs
        let request = try proofRequest(nullifierKey: nullifierKey, statement: statement)
        let response = try await prover.proveTransfer(request)
        let treeContexts = try treeContexts(from: response.resolution, statement: statement)
        return try instruction(proof: proof(from: response.proof), treeContexts: treeContexts)
    }

    /// Checks that a nullifier key derives the spent inputs' nullifiers.
    ///
    /// - Parameter nullifierKey: The sender's nullifier key.
    /// - Throws: ``ValidationError/foreignNullifierKey`` if it doesn't.
    private func check(_ nullifierKey: NullifierKey) throws {
        for input in inputs where input.utxo != nil {
            guard nullifierKey.nullifier(utxoHash: input.hash, blinding: input.blinding) == input.nullifier else {
                throw ValidationError.foreignNullifierKey
            }
        }
    }

    /// Creates the request for the plan's proof from its statement.
    ///
    /// - Parameters:
    ///   - nullifierKey: The sender's checked nullifier key.
    ///   - statement: The plan's ``publicInputs``.
    /// - Returns: The request.
    /// - Throws: An error as ``proofRequest(nullifierKey:)`` describes, except for the key's check.
    private func proofRequest(nullifierKey: NullifierKey, statement: PublicInputs) throws
        -> IndexedTransferProofRequest {
        let senderIdentity = OwnerIdentity.solana(signingPublicKey: payer.bytes)
        let secret = nullifierKey.secretElement
        let requestInputs = try inputs.map { input in
            let isPadding = input.utxo == nil
            return try IndexedTransferProofRequest.Input(
                utxo: Self.witnessUTXO(input.utxo, blinding: input.blinding), isDummy: isPadding,
                treeSlot: input.treeIndex, nullifier: input.nullifier.bigEndianBytes,
                ownerPublicKeyHash: (isPadding ? .zero : senderIdentity).bigEndianBytes,
                nullifierSecret: (isPadding ? .zero : secret).bigEndianBytes,
                commitment: isPadding ? nil : input.hash.bigEndianBytes
            )
        }
        let requestOutputs = try zip(outputs, statement.outputOwnerIdentities).map { output, identity in
            try IndexedTransferProofRequest.Output(
                utxo: Self.witnessUTXO(output.utxo, blinding: output.blinding), isDummy: output.utxo == nil,
                hash: output.published.utxoHash.bigEndianBytes, ownerPublicKeyHash: identity.bigEndianBytes,
                nullifierPublicKey: (output.owner?.nullifierPublicKey ?? .zero).bigEndianBytes
            )
        }
        let trees = try inputTreeIDs.map { id in
            try IndexedTransferProofRequest.Tree(id: id, address: ShieldedPool.tree(id: id).bytes)
        }
        return try IndexedTransferProofRequest(
            trees: trees,
            inputs: requestInputs,
            outputs: requestOutputs,
            publicInputs: statement.elements.map(\.bigEndianBytes),
            outputTreeID: outputTreeID,
            blindingSeed: blindingSeed.bigEndianBytes,
            publicAssets: statement.publicAssets.map(\.bigEndianBytes),
            publicAmounts: statement.publicAmounts.map(\.bigEndianBytes),
            ringProgramID: statement.ringProgramID.bigEndianBytes,
            signerPublicKeyHashes: statement.signerIdentities.map(\.bigEndianBytes),
            inputFlags: statement.inputFlags.bigEndianBytes,
            publishedOutputOwnerPublicKeyHashes: statement.outputOwnerIdentities.map(\.bigEndianBytes)
        )
    }

    /// Creates a slot's UTXO as the witness carries it.
    ///
    /// - Parameters:
    ///   - utxo: The slot's UTXO, or `nil` for padding.
    ///   - blinding: The slot's blinding.
    /// - Returns: The witness UTXO, without data, ring data, or a ring program.
    /// - Throws: An ``RPC/IndexedTransferProofRequest/ValidationError`` if a value isn't 32 bytes.
    private static func witnessUTXO(_ utxo: UTXO?, blinding: Poseidon.Element) throws
        -> IndexedTransferProofRequest.UTXO {
        let zero = Poseidon.Element.zero.bigEndianBytes
        return try IndexedTransferProofRequest.UTXO(
            domain: Poseidon.Element(utxo == nil ? UTXO.dummyHashDomain : UTXO.hashDomain).bigEndianBytes,
            owner: (utxo?.owner ?? .zero).bigEndianBytes,
            asset: (utxo?.asset.commitment ?? .zero).bigEndianBytes,
            amount: Poseidon.Element(utxo?.amount ?? 0).bigEndianBytes,
            blinding: blinding.bigEndianBytes,
            dataHash: zero, ringDataHash: zero, ringProgramID: zero
        )
    }
}
