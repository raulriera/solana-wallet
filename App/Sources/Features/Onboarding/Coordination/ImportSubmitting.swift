/// A workflow that imports submitted recovery words.
@MainActor
protocol ImportSubmitting {
    /// Whether an import is waiting or running.
    var isPending: Bool { get }

    /// Submits recovery words for import.
    ///
    /// - Parameters:
    ///   - phrase: The recovery words.
    ///   - passphrase: The BIP-39 passphrase, including case and whitespace.
    func submit(_ phrase: String, passphrase: String)
}
