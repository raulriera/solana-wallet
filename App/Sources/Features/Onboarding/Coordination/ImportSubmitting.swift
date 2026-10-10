/// Accepts locally validated recovery only after the user explicitly submits it.
@MainActor
protocol ImportSubmitting {
    /// Whether an accepted import is still running, so the screen keeps its input locked until it ends.
    var isPending: Bool { get }

    /// Requests one import without normalizing the original BIP-39 passphrase.
    /// - Parameters:
    ///   - phrase: Recovery words supplied by the phrase-entry screen.
    ///   - passphrase: The original passphrase, including case and whitespace.
    func submit(_ phrase: String, passphrase: String)
}
