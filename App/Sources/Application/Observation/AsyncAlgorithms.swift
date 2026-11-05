//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift Async Algorithms open source project
//
// Copyright (c) 2022 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
//
//===----------------------------------------------------------------------===//

nonisolated extension AsyncSequence where Element: Equatable & SendableMetatype {
  /// Creates an asynchronous sequence that omits repeated elements.
  public func removeDuplicates() -> AsyncRemoveDuplicatesSequence<Self> {
    AsyncRemoveDuplicatesSequence(self) { lhs, rhs in
      lhs == rhs
    }
  }
}

/// An asynchronous sequence that omits repeated elements by testing them with a predicate.
nonisolated public struct AsyncRemoveDuplicatesSequence<Base: AsyncSequence>: AsyncSequence {
  public typealias Element = Base.Element

  /// The iterator for an `AsyncRemoveDuplicatesSequence` instance.
  nonisolated public struct Iterator: AsyncIteratorProtocol {
    public typealias Failure = Base.Failure

    @usableFromInline
    var iterator: Base.AsyncIterator

    @usableFromInline
    let predicate: @Sendable (Element, Element) async -> Bool

    @usableFromInline
    var last: Element?

    @usableFromInline
    init(iterator: Base.AsyncIterator, predicate: @escaping @Sendable (Element, Element) async -> Bool) {
      self.iterator = iterator
      self.predicate = predicate
    }

    @inlinable
    public mutating func next() async rethrows -> Element? {
      try await next(isolation: #isolation)
    }

    /// Returns the next element that differs from the one before it, reading the base sequence on an actor.
    ///
    /// - Parameter actor: The actor to read the base sequence on, or `nil` for none.
    /// - Returns: The next element, or `nil` at the end of the base sequence.
    /// - Throws: The base sequence's error.
    @inlinable
    public mutating func next(isolation actor: isolated (any Actor)?) async throws(Failure) -> Element? {
      guard let last else {
        last = try await iterator.next(isolation: actor)
        return last
      }
      while let element = try await iterator.next(isolation: actor) {
        if await !predicate(last, element) {
          self.last = element
          return element
        }
      }
      return nil
    }
  }

  @usableFromInline
  let base: Base

  @usableFromInline
  let predicate: @Sendable (Element, Element) async -> Bool

  init(_ base: Base, predicate: @escaping @Sendable (Element, Element) async -> Bool) {
    self.base = base
    self.predicate = predicate
  }

  @inlinable
  public func makeAsyncIterator() -> Iterator {
    Iterator(iterator: base.makeAsyncIterator(), predicate: predicate)
  }
}

extension AsyncRemoveDuplicatesSequence: Sendable where Base: Sendable, Base.Element: Sendable {}

@available(*, unavailable)
extension AsyncRemoveDuplicatesSequence.Iterator: Sendable {}

nonisolated extension AsyncSequence {
  /// An `AsyncSequence` that iterates over the adjacent pairs of the original
  /// original `AsyncSequence`.
  ///
  /// ```
  /// for await (first, second) in (1...5).async.adjacentPairs() {
  ///    print("First: \(first), Second: \(second)")
  /// }
  ///
  /// // First: 1, Second: 2
  /// // First: 2, Second: 3
  /// // First: 3, Second: 4
  /// // First: 4, Second: 5
  /// ```
  ///
  /// - Returns: An `AsyncSequence` where the element is a tuple of two adjacent elements
  ///   or the original `AsyncSequence`.
  @inlinable
  public func adjacentPairs() -> AsyncAdjacentPairsSequence<Self> {
    AsyncAdjacentPairsSequence(self)
  }
}

/// An `AsyncSequence` that iterates over the adjacent pairs of the original
/// `AsyncSequence`.
@frozen
nonisolated public struct AsyncAdjacentPairsSequence<Base: AsyncSequence>: AsyncSequence {
  public typealias Element = (Base.Element, Base.Element)

  @usableFromInline
  let base: Base

  @inlinable
  init(_ base: Base) {
    self.base = base
  }

  /// The iterator for an `AsyncAdjacentPairsSequence` instance.
  @frozen
  nonisolated public struct Iterator: AsyncIteratorProtocol {
    public typealias Element = (Base.Element, Base.Element)
    public typealias Failure = Base.Failure

    @usableFromInline
    var base: Base.AsyncIterator

    @usableFromInline
    internal var previousElement: Base.Element?

    @inlinable
    init(_ base: Base.AsyncIterator) {
      self.base = base
    }

    @inlinable
    public mutating func next() async rethrows -> (Base.Element, Base.Element)? {
      try await next(isolation: #isolation)
    }

    /// Returns the next pair of adjacent elements, reading the base sequence on an actor.
    ///
    /// - Parameter actor: The actor to read the base sequence on, or `nil` for none.
    /// - Returns: The next pair, or `nil` at the end of the base sequence.
    /// - Throws: The base sequence's error.
    @inlinable
    public mutating func next(isolation actor: isolated (any Actor)?) async throws(Failure) -> (Base.Element, Base.Element)? {
      if previousElement == nil {
        previousElement = try await base.next(isolation: actor)
      }

      guard let previous = previousElement, let next = try await base.next(isolation: actor) else {
        return nil
      }

      previousElement = next
      return (previous, next)
    }
  }

  @inlinable
  public func makeAsyncIterator() -> Iterator {
    Iterator(base.makeAsyncIterator())
  }
}

extension AsyncAdjacentPairsSequence: Sendable where Base: Sendable, Base.Element: Sendable {}

@available(*, unavailable)
extension AsyncAdjacentPairsSequence.Iterator: Sendable {}
