import ModularArithmetic
import RPC
import Transactions

extension TransactPlan {
    /// The capacity of a UTXO tree's root history, `STATE_ROOT_HISTORY_CAPACITY`.
    private static let utxoRootHistoryCapacity: UInt16 = 500

    /// The capacity of a nullifier tree's root history, `NULLIFIER_TREE_ROOT_HISTORY_CAPACITY`: a
    /// queue batch of 25,000 nullifiers over proof batches of 250.
    private static let nullifierRootHistoryCapacity: UInt16 = 100

    /// Creates the request for the plan's proof on the prover's indexed route.
    ///
    /// The prover resolves each declared tree's roots itself, so the request names the trees in
    /// declaration order, each input's tree and the commitment of each spent UTXO, the 17 public
    /// inputs without the tree slots, and the witness, as zolana's `PreparedIndexedTransfer`
    /// builds them:
    ///
    /// - A spent input carries its UTXO, the sender's identity, and the nullifier secret. A
    ///   padding input carries only its domain and blinding, with zero for the identity and the
    ///   secret; it publishes its own nullifier.
    /// - A real output carries its UTXO, its owner's identity, and its owner's nullifier public key.
    ///   A padding output carries only its domain and blinding, the identity of its view tag, and
    ///   zero for the nullifier public key.
    ///
    /// The request holds the nullifier secret and the blinding seed in plain form; the prover can
    /// link the sender's spends but can't spend, because each spend needs the sender's signature.
    ///
    /// - Parameter nullifierKey: The sender's nullifier key.
    /// - Returns: The request.
    /// - Throws: ``ValidationError/foreignNullifierKey`` if the key doesn't derive the spent
    ///   inputs' nullifiers, or a ``RPC/TransferProofRequest/ValidationError`` or
    ///   ``Transactions/ValidationError`` if a value or a tree account is invalid, which doesn't
    ///   happen.
    func proofRequest(nullifierKey: NullifierKey) throws -> TransferProofRequest {
        try proofRequest(nullifierKey: nullifierKey, statement: publicInputs)
    }

    /// Checks the prover's response against the plan and converts its proof for the instruction.
    ///
    /// The proving key must be the plan's shape's. The resolved trees must be the declared trees,
    /// in declaration order, with root positions inside their histories, so no tree is cache-only.
    /// The resolved roots must reproduce the prover's public input hash from the plan's statement.
    /// No pairing check runs on the device: a proof that doesn't verify fails the transaction's
    /// simulation and can't move funds. `a` is negated and compressed, `c` is compressed, and `b`
    /// is copied.
    ///
    /// - Parameter response: The prover's response to ``proofRequest(nullifierKey:)``.
    /// - Returns: The proof and one tree context per declared tree, in declaration order.
    /// - Throws: ``ValidationError/unexpectedProvingKey``, ``ValidationError/unexpectedTrees``,
    ///   ``ValidationError/rootIndexOutOfRange``, ``ValidationError/invalidRoot``, or
    ///   ``ValidationError/publicInputHashMismatch`` if the response doesn't match the plan,
    ///   ``ProofPoint/ValidationError/invalidCoordinate`` for a coordinate at or above the base
    ///   field's modulus, ``TransactProof/ValidationError/invalidLength`` if `b` doesn't have 128
    ///   bytes, or a ``Transactions/ValidationError`` if a tree account's derivation fails, which
    ///   doesn't happen.
    func proof(from response: TransferProof) throws -> (proof: TransactProof, treeContexts: [TreeContext]) {
        try proof(from: response, statement: publicInputs)
    }

    /// Proves the plan and creates its transact instruction.
    ///
    /// The work runs off the caller's actor: it hashes the request's statement once, waits for the
    /// prover, and checks the response.
    ///
    /// - Parameters:
    ///   - nullifierKey: The sender's nullifier key.
    ///   - prover: The prover, such as a Helius client.
    /// - Returns: The instruction, which the sender signs as the fee payer.
    /// - Throws: An error from ``proofRequest(nullifierKey:)``, the prover, ``proof(from:)``, or
    ///   ``instruction(proof:treeContexts:)``.
    @concurrent
    func instruction(nullifierKey: NullifierKey, prover: some ProofProviding) async throws -> Instruction {
        let statement = publicInputs
        let response = try await prover.proveTransfer(try proofRequest(nullifierKey: nullifierKey, statement: statement))
        let (proof, treeContexts) = try proof(from: response, statement: statement)
        return try instruction(proof: proof, treeContexts: treeContexts)
    }

    /// Creates the request for the plan's proof from its statement.
    ///
    /// - Parameters:
    ///   - nullifierKey: The sender's nullifier key.
    ///   - statement: The plan's ``publicInputs``.
    /// - Returns: The request.
    /// - Throws: An error as ``proofRequest(nullifierKey:)`` describes.
    private func proofRequest(nullifierKey: NullifierKey, statement: PublicInputs) throws -> TransferProofRequest {
        for input in inputs where input.utxo != nil {
            guard nullifierKey.nullifier(utxoHash: input.hash, blinding: input.blinding) == input.nullifier else {
                throw ValidationError.foreignNullifierKey
            }
        }
        let senderIdentity = OwnerIdentity.solana(signingPublicKey: payer.bytes)
        let secret = nullifierKey.secretElement
        let witnessInputs = try inputs.map { input in
            let isPadding = input.utxo == nil
            return try TransferProofRequest.WitnessInput(
                utxo: Self.witnessUTXO(input.utxo, blinding: input.blinding), isDummy: isPadding, treeSlot: input.treeIndex,
                nullifier: input.nullifier.bigEndianBytes, ownerPublicKeyHash: (isPadding ? .zero : senderIdentity).bigEndianBytes,
                nullifierSecret: (isPadding ? .zero : secret).bigEndianBytes
            )
        }
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
            trees: inputTreeIDs.map { try TransferProofRequest.Tree(address: ShieldedPool.tree(id: $0).value, id: $0) },
            inputs: inputs.map {
                try TransferProofRequest.Input(treeSlot: $0.treeIndex, commitment: $0.utxo == nil ? nil : $0.hash.bigEndianBytes, nullifier: nil)
            },
            publicInputs: statement.elements.map(\.bigEndianBytes),
            minContextSlot: nil,
            witness: witness
        )
    }

    /// Checks the prover's response against the plan's statement and converts its proof.
    ///
    /// - Parameters:
    ///   - response: The prover's response.
    ///   - statement: The plan's ``publicInputs``.
    /// - Returns: The proof and one tree context per declared tree, in declaration order.
    /// - Throws: An error as ``proof(from:)`` describes.
    private func proof(from response: TransferProof, statement: PublicInputs) throws -> (proof: TransactProof, treeContexts: [TreeContext]) {
        guard response.provingKeyDigest == shape.provingKeyDigest else { throw ValidationError.unexpectedProvingKey }
        let trees = response.resolution.trees
        let declared = try inputTreeIDs.map { try ShieldedPool.tree(id: $0).value }
        guard trees.map(\.address) == declared, trees.map(\.id) == inputTreeIDs else { throw ValidationError.unexpectedTrees }
        guard trees.allSatisfy({
            $0.utxoRootIndex < Self.utxoRootHistoryCapacity && $0.nullifierRootIndex < Self.nullifierRootHistoryCapacity
        }) else { throw ValidationError.rootIndexOutOfRange }
        let slots = try trees.map { tree in
            guard let utxoRoot = Poseidon.Element(bigEndianBytes: tree.utxoRoot),
                  let nullifierRoot = Poseidon.Element(bigEndianBytes: tree.nullifierRoot) else { throw ValidationError.invalidRoot }
            return PublicInputs.TreeSlot(treeID: tree.id, utxoRoot: utxoRoot, nullifierRoot: nullifierRoot)
        }
        guard statement.hash(treeSlots: slots).bigEndianBytes == response.resolution.publicInputHash else {
            throw ValidationError.publicInputHashMismatch
        }
        let proof = try TransactProof(
            a: ProofPoint.compressed(x: response.a.x, y: response.a.y, negated: true), b: response.b,
            c: ProofPoint.compressed(x: response.c.x, y: response.c.y)
        )
        return (proof, trees.map { TreeContext(utxoTreeRootIndex: $0.utxoRootIndex, nullifierTreeRootIndex: $0.nullifierRootIndex) })
    }

    /// Creates a slot's UTXO as the witness carries it.
    ///
    /// - Parameters:
    ///   - utxo: The slot's UTXO, or `nil` for padding, which carries only its domain and blinding.
    ///   - blinding: The slot's blinding.
    /// - Returns: The witness UTXO, without data, ring data, or a ring program.
    /// - Throws: A ``RPC/TransferProofRequest/ValidationError`` if a value isn't 32 bytes, which
    ///   doesn't happen.
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
