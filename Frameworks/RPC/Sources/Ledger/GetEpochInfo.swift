/// A request for the current epoch, absolute slot, and block height at finalized commitment.
public struct GetEpochInfo: RPCRequest {
    public static let method = "getEpochInfo"

    /// An epoch observation with the absolute slot and block height at which it was read.
    public struct Response: Decodable, Sendable {
        public let epoch: UInt64
        public let absoluteSlot: UInt64
        public let blockHeight: UInt64

        /// Creates an epoch observation with its slot and block height.
        ///
        /// - Parameters:
        ///   - epoch: The current epoch.
        ///   - absoluteSlot: The absolute slot of the observation.
        ///   - blockHeight: The block height of the observation.
        public init(epoch: UInt64, absoluteSlot: UInt64, blockHeight: UInt64) {
            self.epoch = epoch
            self.absoluteSlot = absoluteSlot
            self.blockHeight = blockHeight
        }
    }

    private let configuration: LedgerConfiguration

    /// Creates an epoch request at finalized commitment.
    ///
    /// - Parameter minContextSlot: The earliest evaluation slot, or `nil` for no minimum.
    public init(minContextSlot: UInt64? = nil) {
        configuration = LedgerConfiguration(minContextSlot: minContextSlot)
    }

    public func encode(to encoder: any Encoder) throws {
        var parameters = encoder.unkeyedContainer()
        try parameters.encode(configuration)
    }

    /// Checks that the epoch observation comes from the minimum slot or later.
    ///
    /// - Parameter response: The decoded response.
    /// - Throws: ``RPCError/InvalidResponse/staleContext`` if the observation comes from an earlier slot.
    public func validate(_ response: Response) throws {
        try configuration.validate(contextSlot: response.absoluteSlot)
    }
}
