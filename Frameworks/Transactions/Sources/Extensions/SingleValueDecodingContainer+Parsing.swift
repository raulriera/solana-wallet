extension SingleValueDecodingContainer {
    /// Decodes a string and parses it into a value.
    ///
    /// - Parameters:
    ///   - parse: Parses the decoded text.
    ///   - debugDescription: The description of the error for text that doesn't parse.
    /// - Returns: The parsed value.
    /// - Throws: A decoding error if the value isn't a string, or `DecodingError.dataCorrupted` if it doesn't parse.
    func decode<Value>(parsing parse: (String) throws -> Value, debugDescription: String) throws -> Value {
        let text = try decode(String.self)
        do {
            return try parse(text)
        } catch {
            throw DecodingError.dataCorrupted(DecodingError.Context(
                codingPath: codingPath, debugDescription: debugDescription, underlyingError: error))
        }
    }
}
