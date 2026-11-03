func fieldElement(_ value: UInt8) -> [UInt8] {
    [UInt8](repeating: 0, count: 31) + [value]
}
