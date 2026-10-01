/// Explicit fee and resource requests embedded in a V1 message.
public struct Configuration: Sendable {
    /// The total priority fee in lamports, excluding the base transaction fee.
    public let priorityFeeLamports: UInt64
    /// The maximum number of compute units available to the transaction.
    public let computeUnitLimit: UInt32
    /// The maximum loaded account data size, in bytes.
    public let loadedAccountsDataSizeLimit: UInt32
    /// The requested heap size in bytes, or `nil` for the protocol's 32 KiB default.
    public let heapSize: UInt32?

    /// Creates a configuration without silently clamping resource limits.
    ///
    /// These bounds validate the request; simulation determines whether the chosen
    /// limits are sufficient. The priority fee is a total, not a price per compute unit.
    ///
    /// - Parameters:
    ///   - priorityFeeLamports: The total priority fee; zero is permitted.
    ///   - computeUnitLimit: A value from 1 through 1,400,000.
    ///   - loadedAccountsDataSizeLimit: A value from 1 through 67,108,864 bytes.
    ///   - heapSize: A multiple of 1,024 from 32,768 through 262,144, or `nil`.
    /// - Throws: A ``ValidationError`` identifying an out-of-range resource request.
    public init(
        priorityFeeLamports: UInt64,
        computeUnitLimit: UInt32,
        loadedAccountsDataSizeLimit: UInt32,
        heapSize: UInt32? = nil
    ) throws {
        guard (1...1_400_000).contains(computeUnitLimit) else {
            throw ValidationError.invalidComputeUnitLimit
        }
        guard (1...67_108_864).contains(loadedAccountsDataSizeLimit) else {
            throw ValidationError.invalidLoadedAccountsDataSizeLimit
        }
        try Self.validateHeapSize(heapSize)
        self.priorityFeeLamports = priorityFeeLamports
        self.computeUnitLimit = computeUnitLimit
        self.loadedAccountsDataSizeLimit = loadedAccountsDataSizeLimit
        self.heapSize = heapSize
    }

    /// Validates the heap rule shared by construction and wire decoding.
    ///
    /// - Parameter heapSize: The requested bytes, or `nil` for the protocol default.
    /// - Throws: ``ValidationError/invalidHeapSize`` for an out-of-range or unaligned value.
    static func validateHeapSize(_ heapSize: UInt32?) throws {
        if let heapSize, !(32_768...262_144).contains(heapSize) || heapSize % 1_024 != 0 {
            throw ValidationError.invalidHeapSize
        }
    }
}
