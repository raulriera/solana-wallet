@testable import Transactions

// swift-format-ignore: NeverUseForceTry
extension Mint {
    static func fixture(_ address: String, program: TokenProgram = .token, decimals: UInt8, name: String? = nil,
                        symbol: String? = nil) -> Mint {
        let metadata = name == nil && symbol == nil ? nil : TokenMetadata(name: name, symbol: symbol)
        return Mint(address: try! Address(address), program: program, decimals: decimals, metadata: metadata)
    }

    static func fixture(symbol: String) -> Mint {
        let bytes = Array(symbol.utf8.prefix(32))
        let address = try! Address(bytes: bytes + [UInt8](repeating: 0, count: 32 - bytes.count))
        return Mint(address: address, program: .token, decimals: 0, metadata: TokenMetadata(name: nil, symbol: symbol))
    }
}
