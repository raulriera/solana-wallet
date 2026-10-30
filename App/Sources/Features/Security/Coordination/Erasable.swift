/// Saved data that a reset can delete.
@MainActor
protocol Erasable {
    /// Stops saving and deletes the saved data.
    ///
    /// - Throws: A storage error if the data can't be deleted.
    func erase() async throws
}
