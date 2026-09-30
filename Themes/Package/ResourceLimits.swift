/// Resource ceilings for untrusted package input, independent of appearance choices.
enum ResourceLimits {
    static let manifestBytes = 1_048_576
    static let assetBytes = 16_777_216
    static let totalAssetBytes = 67_108_864
    static let imagePixels = 16_777_216

    /// Rejects bytes before retaining input beyond a file or remaining-package budget.
    /// - Parameters:
    ///   - count: The proposed byte count.
    ///   - limit: The file limit or remaining aggregate allowance.
    ///   - path: The author-facing location of the input.
    /// - Throws: A validation error if the byte count is outside the allowed range.
    static func checkBytes(_ count: Int64, limit: Int, path: String) throws {
        guard count >= 0, count <= limit else {
            throw ValidationError(path: path, reason: "Exceeds the \(limit)-byte limit for this file or remaining package budget.")
        }
    }
}
