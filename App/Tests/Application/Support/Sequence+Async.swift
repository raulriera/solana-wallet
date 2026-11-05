extension Sequence where Element: Sendable {
    var async: AsyncStream<Element> {
        AsyncStream { continuation in
            for element in self { continuation.yield(element) }
            continuation.finish()
        }
    }
}
