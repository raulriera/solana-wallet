extension Array where Element: Hashable {
    /// Returns the elements in their original order, without later repeats.
    ///
    /// - Returns: The first occurrence of each element.
    func uniqued() -> [Element] {
        uniqued(by: \.self)
    }
}

extension Array {
    /// Splits the elements, in order, into consecutive batches of at most a given size.
    ///
    /// - Parameter size: The largest batch size, greater than zero.
    /// - Returns: The batches in order.
    func batches(of size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
    }
}

extension Array {
    /// Returns the elements in their original order, without later elements whose key repeats an earlier one.
    ///
    /// - Parameter key: The closure that returns an element's identity.
    /// - Returns: The first element with each key.
    func uniqued<Key: Hashable>(by key: (Element) -> Key) -> [Element] {
        var seen = Set<Key>()
        return filter { seen.insert(key($0)).inserted }
    }
}
