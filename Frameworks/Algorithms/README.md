# Algorithms

Sequence and asynchronous sequence algorithms copied from Apple's open-source [Swift Algorithms](https://github.com/apple/swift-algorithms) and [Swift Async Algorithms](https://github.com/apple/swift-async-algorithms) packages, with their license headers. The code builds with the app's own security settings and keeps the packages' API, so code reads as it would with them.

## Usage

```swift
import Algorithms

for chunk in [1, 2, 3, 4, 5].chunks(ofCount: 2) {
    // [1, 2], [3, 4], [5]
}
```

## Adding an algorithm

Copy the algorithm's source from a tagged release and keep its license header.
