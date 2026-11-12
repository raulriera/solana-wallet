extension Sequence where Element: Sendable {
    /// Returns the results of transforming each element in its own child task, in the sequence's order.
    ///
    /// - Parameter transform: The work for one element.
    /// - Returns: Each element's result, in the sequence's order.
    /// - Throws: The first error that any transform throws, after which the other child tasks are cancelled.
    public func concurrentMap<Result: Sendable>(
        _ transform: @escaping @Sendable (Element) async throws -> Result
    ) async throws -> [Result] {
        try await withThrowingTaskGroup(of: (Int, Result).self) { group in
            var count = 0
            for (index, element) in enumerated() {
                group.addTask { (index, try await transform(element)) }
                count += 1
            }
            var results = [Result?](repeating: nil, count: count)
            for try await (index, result) in group { results[index] = result }
            return results.compactMap(\.self)
        }
    }
}
