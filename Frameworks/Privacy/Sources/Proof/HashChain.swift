import ModularArithmetic

/// The Poseidon hash chains that fold a transact proof's public inputs, as zolana's hasher defines
/// them.
///
/// The chains carry no length and no domain tag, so each one is injective only over lists of one
/// fixed length; the proof's shape fixes every length. An empty list chains to zero and a single
/// element chains to itself. The private transaction hash folds its slots with a different chain,
/// ``PrivateTransactionHash/nonzeroChain(_:)``.
enum HashChain {
    /// Folds elements from the left, three at a time, `hash_chain_4`.
    ///
    /// The chain starts at the first element, and each group of up to three following elements
    /// folds in as `Poseidon(chain, g0, g1, g2)`, with zeros completing a short last group.
    ///
    /// - Parameter elements: The elements, in order.
    /// - Returns: The chain.
    static func left4(_ elements: [Poseidon.Element]) -> Poseidon.Element {
        guard let first = elements.first else { return .zero }
        return stride(from: 1, to: elements.count, by: 3).reduce(first) { chain, start in
            let group = groupOfThree(elements[start..<min(start + 3, elements.count)])
            return Poseidon.hash(chain, group[0], group[1], group[2])
        }
    }

    /// Folds elements from the right, three at a time, `right_hash_chain_4`.
    ///
    /// The chain starts at the last element, and each group of up to three preceding elements,
    /// walking backwards, folds in as `Poseidon(g0, g1, g2, chain)`. The leftmost group is the short
    /// one, and its elements stay left-aligned before the zeros that complete it. A suffix of zeros
    /// therefore folds to a value that depends only on its length, ``zeroSuffix(groups:)``.
    ///
    /// - Parameter elements: The elements, in order, such as a slot list padded with zeros to its
    ///   circuit width.
    /// - Returns: The chain.
    static func right4(_ elements: [Poseidon.Element]) -> Poseidon.Element {
        guard let last = elements.last else { return .zero }
        let prefix = elements.dropLast()
        return stride(from: prefix.count, to: 0, by: -3).reduce(last) { chain, end in
            let group = groupOfThree(prefix[max(0, end - 3)..<end])
            return Poseidon.hash(group[0], group[1], group[2], chain)
        }
    }

    /// Folds elements from the right, one at a time, `create_right_hash_chain_from_slice`.
    ///
    /// The chain starts at the last element, and each preceding element, walking backwards, folds
    /// in as `Poseidon(element, chain)`.
    ///
    /// - Parameter elements: The elements, in order.
    /// - Returns: The chain.
    static func right(_ elements: [Poseidon.Element]) -> Poseidon.Element {
        guard let last = elements.last else { return .zero }
        return elements.dropLast().reversed().reduce(last) { chain, element in Poseidon.hash(element, chain) }
    }

    /// Returns the right chain of `1 + 3 × groups` zeros, `ZERO_SUFFIX_CHAINS[groups]`.
    ///
    /// The value is `Z(0) = 0` and `Z(k) = Poseidon(0, 0, 0, Z(k - 1))`.
    ///
    /// - Parameter groups: The number of three-element groups after the first zero.
    /// - Returns: The chain.
    static func zeroSuffix(groups: Int) -> Poseidon.Element {
        right4(Array(repeating: .zero, count: 1 + 3 * groups))
    }

    /// Completes a group of at most three elements with zeros.
    ///
    /// - Parameter elements: One to three elements.
    /// - Returns: Exactly three elements.
    private static func groupOfThree(_ elements: ArraySlice<Poseidon.Element>) -> [Poseidon.Element] {
        Array(elements) + Array(repeating: .zero, count: 3 - elements.count)
    }
}
