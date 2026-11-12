import Algorithms

nonisolated extension AsyncSequence {
    /// Creates an asynchronous sequence of the known values that replace another known value.
    ///
    /// A known value is a non-`nil` element. Repeated elements are omitted, and a change from or to `nil` is not a
    /// change, so the first known value and the first known value after `nil` are skipped.
    ///
    /// - Returns: An asynchronous sequence of each known value that differs from the known value before it.
    func changes<Wrapped>() -> some AsyncSequence<Wrapped, Failure>
    where Element == Wrapped?, Wrapped: Equatable & SendableMetatype {
        AsyncChangesSequence(base: removeDuplicates().adjacentPairs())
    }
}

/// An asynchronous sequence of the known values that replace another known value, read on the caller's actor.
nonisolated struct AsyncChangesSequence<Base: AsyncSequence, Wrapped>: AsyncSequence
where Base.Element == (Wrapped?, Wrapped?) {
    let base: Base

    /// Creates the iterator that reads the base sequence's adjacent pairs.
    ///
    /// - Returns: An iterator over the known values that replace another known value.
    func makeAsyncIterator() -> Iterator {
        Iterator(base: base.makeAsyncIterator())
    }

    /// The iterator for an `AsyncChangesSequence` instance.
    struct Iterator: AsyncIteratorProtocol {
        var base: Base.AsyncIterator

        /// Returns the next known value that replaces another known value.
        ///
        /// - Returns: The next change, or `nil` at the end of the base sequence.
        /// - Throws: The base sequence's error.
        mutating func next() async throws(Base.Failure) -> Wrapped? {
            try await next(isolation: #isolation)
        }

        /// Returns the next known value that replaces another known value, reading the base sequence on an actor.
        ///
        /// - Parameter actor: The actor to read the base sequence on, or `nil` for none.
        /// - Returns: The next change, or `nil` at the end of the base sequence.
        /// - Throws: The base sequence's error.
        mutating func next(isolation actor: isolated (any Actor)?) async throws(Base.Failure) -> Wrapped? {
            while case (let previous, let current)? = try await base.next(isolation: actor) {
                if previous != nil, let current { return current }
            }
            return nil
        }
    }
}
