/// Shared saved data that a reset deletes, such as the contacts or the currency choice that every window shows.
@MainActor
protocol Erasable {
    /// Deletes what's saved, so every window that shows it starts over.
    /// - Throws: A storage error, which keeps what's saved.
    func erase() async throws
}
