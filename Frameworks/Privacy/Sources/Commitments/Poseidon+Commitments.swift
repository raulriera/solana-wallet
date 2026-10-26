extension Poseidon {
    /// Hashes a fixed list of field elements, such as the inputs of a commitment.
    ///
    /// The commitments in this module each pass a fixed count of one to seven inputs, which
    /// ``hash(_:)`` always accepts, so this overload doesn't throw.
    ///
    /// - Parameters:
    ///   - first: The first input.
    ///   - rest: Up to eleven more inputs.
    /// - Returns: The hash.
    /// - Precondition: There are at most twelve inputs.
    static func hash(_ first: Element, _ rest: Element...) -> Element {
        // swift-format-ignore: NeverUseForceTry
        // One to twelve inputs always have parameters; only a thirteenth input could throw.
        try! hash([first] + rest)
    }
}
