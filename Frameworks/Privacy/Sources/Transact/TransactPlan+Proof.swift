import ModularArithmetic
import RPC
import Transactions

extension TransactPlan {
    /// Reads each declared tree's proofs for the plan's inputs and checks them.
    ///
    /// - Parameter indexer: The indexer.
    /// - Returns: One witness per declared tree, in declaration order.
    /// - Throws: An error from the indexer or ``TreeWitness/init(treeID:inclusionProofs:nonInclusionProofs:)``, or a
    ///   ``Transactions/ValidationError`` if a tree account's derivation fails.
    func treeWitnesses(using indexer: some PrivateNoteProviding) async throws -> [TreeWitness] {
        let reads = try inputTreeIDs.enumerated().map { index, id in
            let slots = inputs.filter { Int($0.treeIndex) == index }
            return TreeRead(id: id, tree: try ShieldedPool.tree(id: id).value,
                            leaves: slots.filter { $0.utxo != nil }.map(\.hash.bigEndianBytes),
                            nullifiers: slots.map(\.nullifier.bigEndianBytes))
        }
        return try await withThrowingTaskGroup(of: (Int, TreeWitness).self) { group in
            for (index, read) in reads.enumerated() {
                group.addTask {
                    async let inclusion = indexer.merkleProofs(for: read.leaves, inTree: read.tree)
                    async let nonInclusion = indexer.nonInclusionProofs(for: read.nullifiers, inTree: read.tree)
                    let (included, excluded) = try await (inclusion, nonInclusion)
                    return (index, try TreeWitness(treeID: read.id, inclusionProofs: included, nonInclusionProofs: excluded))
                }
            }
            var witnesses = [TreeWitness?](repeating: nil, count: reads.count)
            for try await (index, witness) in group { witnesses[index] = witness }
            return witnesses.compactMap(\.self)
        }
    }

    /// Creates the request for the plan's proof.
    ///
    /// - Parameters:
    ///   - nullifierKey: The sender's nullifier key.
    ///   - trees: The declared trees' witnesses, in declaration order.
    /// - Returns: The request.
    /// - Throws: ``ValidationError/foreignNullifierKey`` if the key doesn't derive the spent
    ///   inputs' nullifiers, ``ValidationError/inconsistentProofs`` unless each tree has one proof of each kind
    ///   for each of its inputs, in order, or a ``RPC/TransferProofRequest/ValidationError`` if a value is
    ///   invalid.
    func proofRequest(nullifierKey: NullifierKey, trees: [TreeWitness]) throws -> TransferProofRequest {
        try check(nullifierKey)
        return try proofRequest(nullifierKey: nullifierKey, statement: publicInputs, trees: trees)
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
    ///   - provider: The indexer and prover.
    /// - Returns: The transact instruction.
    /// - Throws: An error from ``proofRequest(nullifierKey:trees:)``, ``treeWitnesses(using:)``, the prover,
    ///   ``proof(from:)``, or ``instruction(proof:treeContexts:)``.
    @concurrent
    func instruction(nullifierKey: NullifierKey, provider: some PrivateNoteProviding & ProofProviding) async throws -> Instruction {
        try check(nullifierKey)
        let trees = try await treeWitnesses(using: provider)
        let request = try proofRequest(nullifierKey: nullifierKey, statement: publicInputs, trees: trees)
        let response = try await provider.proveTransfer(request)
        return try instruction(proof: proof(from: response), treeContexts: trees.map(\.context))
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

    /// Creates the request for the plan's proof from its statement and its trees' witnesses.
    ///
    /// - Parameters:
    ///   - nullifierKey: The sender's checked nullifier key.
    ///   - statement: The plan's ``publicInputs``.
    ///   - trees: The declared trees' witnesses, in declaration order.
    /// - Returns: The request.
    /// - Throws: An error as ``proofRequest(nullifierKey:trees:)`` describes, except for the key's check.
    private func proofRequest(nullifierKey: NullifierKey, statement: PublicInputs, trees: [TreeWitness]) throws
        -> TransferProofRequest {
        guard trees.map(\.slot.treeID) == inputTreeIDs else { throw ValidationError.inconsistentProofs }
        let senderIdentity = OwnerIdentity.solana(signingPublicKey: payer.bytes)
        let secret = nullifierKey.secretElement
        var inclusionProofs = trees.map { $0.inclusionProofs[...] }
        var nonInclusionProofs = trees.map { $0.nonInclusionProofs[...] }
        var witnessInputs: [TransferProofRequest.WitnessInput] = []
        for input in inputs {
            let tree = Int(input.treeIndex)
            let isPadding = input.utxo == nil
            let inclusionProof = isPadding ? nil : inclusionProofs[tree].popFirst()
            guard let nonInclusionProof = nonInclusionProofs[tree].popFirst(),
                  nonInclusionProof.nullifier == input.nullifier.bigEndianBytes,
                  isPadding || inclusionProof?.leaf == input.hash.bigEndianBytes else { throw ValidationError.inconsistentProofs }
            witnessInputs.append(try TransferProofRequest.WitnessInput(
                utxo: Self.witnessUTXO(input.utxo, blinding: input.blinding), isDummy: isPadding, treeSlot: input.treeIndex,
                nullifier: input.nullifier.bigEndianBytes, ownerPublicKeyHash: (isPadding ? .zero : senderIdentity).bigEndianBytes,
                nullifierSecret: (isPadding ? .zero : secret).bigEndianBytes, inclusionProof: inclusionProof,
                nonInclusionProof: nonInclusionProof
            ))
        }
        guard inclusionProofs.allSatisfy(\.isEmpty), nonInclusionProofs.allSatisfy(\.isEmpty) else { throw ValidationError.inconsistentProofs }
        let witnessOutputs = try zip(outputs, statement.outputOwnerIdentities).map { output, identity in
            try TransferProofRequest.WitnessOutput(
                utxo: Self.witnessUTXO(output.utxo, blinding: output.blinding), isDummy: output.utxo == nil,
                hash: output.published.utxoHash.bigEndianBytes, ownerPublicKeyHash: identity.bigEndianBytes,
                nullifierPublicKey: (output.owner?.nullifierPublicKey ?? .zero).bigEndianBytes
            )
        }
        let witness = try TransferProofRequest.Witness(
            inputs: witnessInputs,
            outputs: witnessOutputs,
            outputTreeID: outputTreeID,
            blindingSeed: blindingSeed.bigEndianBytes,
            externalDataHash: externalData.hash,
            privateTransactionHash: privateTransactionHash.bigEndianBytes,
            publicAssets: statement.publicAssets.map(\.bigEndianBytes),
            publicAmounts: statement.publicAmounts.map(\.bigEndianBytes),
            ringProgramID: statement.ringProgramID.bigEndianBytes,
            signerPublicKeyHashes: statement.signerIdentities.map(\.bigEndianBytes),
            inputFlags: statement.inputFlags.bigEndianBytes,
            publishedOutputOwnerPublicKeyHashes: statement.outputOwnerIdentities.map(\.bigEndianBytes),
            cacheTreeID: statement.cacheTreeID.bigEndianBytes,
            cacheReadHashChain: statement.cacheReadHashChain.bigEndianBytes
        )
        return try TransferProofRequest(
            treeSlots: trees.map {
                try TransferProofRequest.TreeSlot(id: $0.slot.treeID, utxoRoot: $0.slot.utxoRoot.bigEndianBytes,
                                                  nullifierRoot: $0.slot.nullifierRoot.bigEndianBytes)
            },
            publicInputHash: statement.hash(treeSlots: trees.map(\.slot)).bigEndianBytes,
            witness: witness
        )
    }

    /// Creates a slot's UTXO as the witness carries it.
    ///
    /// - Parameters:
    ///   - utxo: The slot's UTXO, or `nil` for padding.
    ///   - blinding: The slot's blinding.
    /// - Returns: The witness UTXO, without data, ring data, or a ring program.
    /// - Throws: A ``RPC/TransferProofRequest/ValidationError`` if a value isn't 32 bytes.
    private static func witnessUTXO(_ utxo: UTXO?, blinding: Poseidon.Element) throws -> TransferProofRequest.UTXO {
        let zero = Poseidon.Element.zero.bigEndianBytes
        return try TransferProofRequest.UTXO(
            domain: Poseidon.Element(utxo == nil ? UTXO.dummyHashDomain : UTXO.hashDomain).bigEndianBytes,
            owner: (utxo?.owner ?? .zero).bigEndianBytes,
            asset: (utxo.map { PackedBytes.hash32($0.mint) } ?? .zero).bigEndianBytes,
            amount: Poseidon.Element(utxo?.amount ?? 0).bigEndianBytes,
            blinding: blinding.bigEndianBytes,
            dataHash: zero, ringDataHash: zero, ringProgramID: zero
        )
    }
}

/// The values of one declared tree's two proof reads.
private struct TreeRead: Sendable {
    let id: UInt16
    /// The tree account's base-58 address.
    let tree: String
    /// The UTXO hashes of the tree's spent inputs, in slot order.
    let leaves: [[UInt8]]
    /// The nullifiers of the tree's input slots, padding included, in slot order.
    let nullifiers: [[UInt8]]
}
