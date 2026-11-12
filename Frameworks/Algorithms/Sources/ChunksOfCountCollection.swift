//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift Algorithms open source project
//
// Copyright (c) 2020 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
//
//===----------------------------------------------------------------------===//

/// A collection that presents the elements of its base collection in
/// `SubSequence` chunks of any given count.
///
/// A `ChunksOfCountCollection` is a lazy view on the base `Collection`, but it
/// does not implicitly confer laziness on algorithms applied to its result. In
/// other words, for ordinary collections `c`:
///
/// * `c.chunks(ofCount: 3)` does not create new storage
/// * `c.chunks(ofCount: 3).map(f)` maps eagerly and returns a new array
/// * `c.lazy.chunks(ofCount: 3).map(f)` maps lazily and returns a
///   `LazyMapCollection`
public struct ChunksOfCountCollection<Base: Collection> {
  public typealias Element = Base.SubSequence

  @usableFromInline
  internal let base: Base

  @usableFromInline
  internal let chunkCount: Int

  @usableFromInline
  internal var endOfFirstChunk: Base.Index

  ///  Creates a view instance that presents the elements of `base` in
  ///  `SubSequence` chunks of the given count.
  ///
  /// - Complexity: O(*n*), because the start index is pre-computed.
  @inlinable
  internal init(_base: Base, _chunkCount: Int) {
    self.base = _base
    self.chunkCount = _chunkCount

    self.endOfFirstChunk = _base.index(
      _base.startIndex, offsetBy: _chunkCount,
      limitedBy: _base.endIndex
    ) ?? _base.endIndex
  }
}

extension ChunksOfCountCollection: Collection {
  public struct Index {
    @usableFromInline
    internal let baseRange: Range<Base.Index>

    @inlinable
    internal init(_baseRange: Range<Base.Index>) {
      self.baseRange = _baseRange
    }
  }

  /// - Complexity: O(1)
  @inlinable
  public var startIndex: Index {
    Index(_baseRange: base.startIndex..<endOfFirstChunk)
  }

  @inlinable
  public var endIndex: Index {
    Index(_baseRange: base.endIndex..<base.endIndex)
  }

  /// - Complexity: O(1)
  @inlinable
  public subscript(i: Index) -> Element {
    precondition(i != endIndex, "Index out of range")
    return base[i.baseRange]
  }

  @inlinable
  public func index(after i: Index) -> Index {
    precondition(i != endIndex, "Advancing past end index")
    let baseIdx = base.index(
      i.baseRange.upperBound, offsetBy: chunkCount,
      limitedBy: base.endIndex
    ) ?? base.endIndex
    return Index(_baseRange: i.baseRange.upperBound..<baseIdx)
  }
}

extension ChunksOfCountCollection.Index: Comparable {
  @inlinable
  public static func == (lhs: ChunksOfCountCollection.Index,
                         rhs: ChunksOfCountCollection.Index) -> Bool {
    lhs.baseRange.lowerBound == rhs.baseRange.lowerBound
  }

  @inlinable
  public static func < (lhs: ChunksOfCountCollection.Index,
                        rhs: ChunksOfCountCollection.Index) -> Bool {
    lhs.baseRange.lowerBound < rhs.baseRange.lowerBound
  }
}

extension ChunksOfCountCollection:
  BidirectionalCollection, RandomAccessCollection
where Base: RandomAccessCollection {
  @inlinable
  public func index(before i: Index) -> Index {
    precondition(i != startIndex, "Advancing past start index")

    var offset = chunkCount
    if i.baseRange.lowerBound == base.endIndex {
      let remainder = base.count % chunkCount
      if remainder != 0 {
        offset = remainder
      }
    }

    let baseIdx = base.index(
      i.baseRange.lowerBound, offsetBy: -offset,
      limitedBy: base.startIndex
    ) ?? base.startIndex
    return Index(_baseRange: baseIdx..<i.baseRange.lowerBound)
  }
}

extension ChunksOfCountCollection {
  @inlinable
  public func distance(from start: Index, to end: Index) -> Int {
    let distance =
      base.distance(from: start.baseRange.lowerBound,
                    to: end.baseRange.lowerBound)
    let (quotient, remainder) =
      distance.quotientAndRemainder(dividingBy: chunkCount)
    return quotient + remainder.signum()
  }

  @inlinable
  public var count: Int {
    let (quotient, remainder) =
      base.count.quotientAndRemainder(dividingBy: chunkCount)
    return quotient + remainder.signum()
  }

  @inlinable
  public func index(
    _ i: Index, offsetBy offset: Int, limitedBy limit: Index
  ) -> Index? {
    guard offset != 0 else { return i }
    guard limit != i else { return nil }

    if offset > 0 {
      return limit > i
        ? offsetForward(i, offsetBy: offset, limit: limit)
        : offsetForward(i, offsetBy: offset)
    } else {
      return limit < i
        ? offsetBackward(i, offsetBy: offset, limit: limit)
        : offsetBackward(i, offsetBy: offset)
    }
  }

  @inlinable
  public func index(_ i: Index, offsetBy distance: Int) -> Index {
    guard distance != 0 else { return i }

    let idx = distance > 0
        ? offsetForward(i, offsetBy: distance)
        : offsetBackward(i, offsetBy: distance)
    guard let index = idx else {
      fatalError("Out of bounds")
    }
    return index
  }

  @inlinable
  internal func offsetForward(
    _ i: Index, offsetBy distance: Int, limit: Index? = nil
  ) -> Index? {
    assert(distance > 0)

    return makeOffsetIndex(
      from: i, baseBound: base.endIndex,
      distance: distance, baseDistance: distance * chunkCount,
      limit: limit, by: >
    )
  }

  @inlinable
  internal func computeOffsetBackwardBaseDistance(
    _ i: Index, _ distance: Int
  ) -> Int {
    if i == endIndex {
      let remainder = base.count % chunkCount
      if remainder != 0 {
        return ((distance + 1) * chunkCount) - remainder
      }
    }
    return distance * chunkCount
  }

  @inlinable
  internal func offsetBackward(
    _ i: Index, offsetBy distance: Int, limit: Index? = nil
  ) -> Index? {
    assert(distance < 0)
    let baseDistance =
        computeOffsetBackwardBaseDistance(i, distance)
    return makeOffsetIndex(
      from: i, baseBound: base.startIndex,
      distance: distance, baseDistance: baseDistance,
      limit: limit, by: <
    )
  }

  @inlinable
  internal func makeOffsetIndex(
    from i: Index, baseBound: Base.Index, distance: Int, baseDistance: Int,
    limit: Index?, by limitFn: (Base.Index, Base.Index) -> Bool
  ) -> Index? {
    let baseIdx = base.index(
      i.baseRange.lowerBound, offsetBy: baseDistance,
      limitedBy: baseBound
    )

    if let limit {
      if baseIdx == nil {
        if baseDistance > 0 && limit == endIndex {
          if self.distance(from: i, to: limit) < distance {
            return nil
          }
        } else {
          return nil
        }
      }

      let baseStartIdx = baseIdx ?? baseBound
      if limitFn(baseStartIdx, limit.baseRange.lowerBound) {
        return nil
      }
    }

    let baseStartIdx = baseIdx ?? baseBound
    let baseEndIdx = base.index(
      baseStartIdx, offsetBy: chunkCount, limitedBy: base.endIndex
    ) ?? base.endIndex

    return Index(_baseRange: baseStartIdx..<baseEndIdx)
  }
}

extension Collection {
  /// Returns a collection of subsequences, each with up to the specified
  /// length.
  ///
  /// If the number of elements in the collection is evenly divided by `count`,
  /// then every chunk will have a length equal to `count`. Otherwise, every
  /// chunk but the last will have a length equal to `count`, with the
  /// remaining elements in the last chunk.
  ///
  ///     let numbers = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
  ///     for chunk in numbers.chunks(ofCount: 5) {
  ///         print(chunk)
  ///     }
  ///     // [1, 2, 3, 4, 5]
  ///     // [6, 7, 8, 9, 10]
  ///
  ///     for chunk in numbers.chunks(ofCount: 3) {
  ///         print(chunk)
  ///     }
  ///     // [1, 2, 3]
  ///     // [4, 5, 6]
  ///     // [7, 8, 9]
  ///     // [10]
  ///
  /// - Parameter count: The desired size of each chunk.
  /// - Returns: A collection of consecutive, non-overlapping subsequences of
  ///   this collection, where each subsequence (except possibly the last) has
  ///   the length `count`.
  ///
  /// - Complexity: O(1) if the collection conforms to `RandomAccessCollection`;
  ///   otherwise, O(*k*), where *k* is equal to `count`.
  ///
  @inlinable
  public func chunks(ofCount count: Int) -> ChunksOfCountCollection<Self> {
    precondition(count > 0, "Cannot chunk with count <= 0!")
    return ChunksOfCountCollection(_base: self, _chunkCount: count)
  }
}

extension ChunksOfCountCollection.Index: Hashable where Base.Index: Hashable {}

extension ChunksOfCountCollection: LazySequenceProtocol
  where Base: LazySequenceProtocol {}

extension ChunksOfCountCollection: LazyCollectionProtocol
  where Base: LazyCollectionProtocol {}

