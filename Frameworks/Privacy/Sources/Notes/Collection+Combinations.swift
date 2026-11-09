extension Collection {
    /// Returns every combination of a number of the collection's elements.
    ///
    /// - Parameter count: The number of elements in each combination.
    /// - Returns: The combinations, each in the collection's order, ordered by their elements' positions; a single
    ///   empty combination for a count of zero, and none for a count above the collection's.
    func combinations(ofCount count: Int) -> [[Element]] {
        guard count > 0 else { return [[]] }
        return indices.flatMap { index in
            self[self.index(after: index)...].combinations(ofCount: count - 1).map { [self[index]] + $0 }
        }
    }
}
