import Algorithms
import ModularArithmetic

/// The Poseidon hash chains that fold a transact proof's public inputs.
enum HashChain {
    /// Folds elements from the left, three at a time.
    ///
    /// - Parameter elements: The elements, in order.
    /// - Returns: The chain.
    static func left4(_ elements: [Poseidon.Element]) -> Poseidon.Element {
        guard let first = elements.first else { return .zero }
        return elements.dropFirst().chunks(ofCount: 3).reduce(first) { chain, chunk in
            let group = groupOfThree(chunk)
            return Poseidon.hash(chain, group[0], group[1], group[2])
        }
    }

    /// Folds elements from the right, three at a time.
    ///
    /// - Parameter elements: The elements, in order.
    /// - Returns: The chain.
    static func right4(_ elements: [Poseidon.Element]) -> Poseidon.Element {
        guard let last = elements.last else { return .zero }
        let prefix = elements.dropLast()
        return stride(from: prefix.count, to: 0, by: -3).reduce(last) { chain, end in
            let group = groupOfThree(prefix[max(0, end - 3)..<end])
            return Poseidon.hash(group[0], group[1], group[2], chain)
        }
    }

    /// Folds elements from the right, one at a time.
    ///
    /// - Parameter elements: The elements, in order.
    /// - Returns: The chain.
    static func right(_ elements: [Poseidon.Element]) -> Poseidon.Element {
        guard let last = elements.last else { return .zero }
        return elements.dropLast().reversed().reduce(last) { chain, element in Poseidon.hash(element, chain) }
    }

    /// Returns the right chain of `1 + 3 × groups` zeros.
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
