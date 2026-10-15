extension Array where Element: Hashable {
    /// The elements in their original order, without later repeats.
    /// - Returns: The first occurrence of each element.
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
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
