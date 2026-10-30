import ModularArithmetic

/// The private transaction hash, a public input that binds a transact proof's slots.
enum PrivateTransactionHash {
    /// Folds the nonzero elements into a Poseidon hash chain.
    ///
    /// - Parameter elements: The elements in slot order.
    /// - Returns: The chain, or zero if every element is zero.
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
    /// - Returns: The private transaction hash.
    static func hash(inputs: [Poseidon.Element], outputs: [Poseidon.Element], blinding: Poseidon.Element) -> Poseidon.Element {
        Poseidon.hash(nonzeroChain(inputs), nonzeroChain(outputs), .zero, blinding)
    }
}
