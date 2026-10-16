extension Array where Element: Hashable {
    /// The elements in their original order, without later repeats.
    /// - Returns: The first occurrence of each element.
    func uniqued() -> [Element] {
        uniqued(by: \.self)
    }
}

extension Array {
    /// Splits the elements, in order, into consecutive batches no larger than one request allows.
    /// - Parameter size: The largest batch, greater than zero.
    /// - Returns: Full batches, followed by a shorter last batch for any remainder.
    func batches(of size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
    }
}

extension Array {
    /// The elements in their original order, without later elements that repeat an earlier one's key.
    /// - Parameter key: The identity of an element.
    /// - Returns: The first element with each key.
    func uniqued<Key: Hashable>(by key: (Element) -> Key) -> [Element] {
        var seen = Set<Key>()
        return filter { seen.insert(key($0)).inserted }
    }
}
