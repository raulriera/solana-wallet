import ModularArithmetic

/// The private transaction hash, a public input that binds a transact proof's slots.
///
/// The hash is `Poseidon(chain(inputs), chain(outputs), chain(address nullifiers), blinding)`, where
/// each chain is zolana's nonzero hash chain. Padding slots enter as zero, so their positions don't
/// change the hash. Peer-to-peer transfers create no addresses, so the address chain is zero. The
/// blinding is the private transaction blinding of ``TransactBlinding``, which keeps observers from
/// testing candidate input hashes against the hash.
enum PrivateTransactionHash {
    /// Folds field elements into zolana's nonzero hash chain.
    ///
    /// The chain skips zeros, starts at the first nonzero element, and folds each later one as
    /// `Poseidon(chain, element)`. A list without a nonzero element chains to zero.
    ///
    /// - Parameter elements: The elements in slot order.
    /// - Returns: The chain.
    static func nonzeroChain(_ elements: [Poseidon.Element]) -> Poseidon.Element {
        elements.reduce(into: .zero) { chain, element in
            guard element != .zero else { return }
            chain = chain == .zero ? element : Poseidon.hash(chain, element)
        }
    }

    /// Hashes a transact's slots.
    ///
    /// - Parameters:
    ///   - inputs: Each input slot's UTXO hash, or zero for padding.
    ///   - outputs: Each output slot's UTXO hash, or zero for padding.
    ///   - blinding: The private transaction blinding.
    /// - Returns: `Poseidon(chain(inputs), chain(outputs), 0, blinding)`.
    static func hash(inputs: [Poseidon.Element], outputs: [Poseidon.Element], blinding: Poseidon.Element) -> Poseidon.Element {
        Poseidon.hash(nonzeroChain(inputs), nonzeroChain(outputs), .zero, blinding)
    }
}
