extension Poseidon {
    /// Hashes one to twelve field elements.
    ///
    /// - Parameters:
    ///   - first: The first input.
    ///   - rest: Up to eleven more inputs.
    /// - Returns: The hash.
    static func hash(_ first: Element, _ rest: Element...) -> Element {
        // swift-format-ignore: NeverUseForceTry
        try! hash([first] + rest)
    }
}
