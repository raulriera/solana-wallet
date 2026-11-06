nonisolated extension Optional {
    /// Whether a value is present; setting it to `false` clears the value.
    var isPresented: Bool {
        get { self != nil }
        set { if !newValue { self = nil } }
    }
}

nonisolated extension Optional where Wrapped: Equatable {
    /// Accesses whether a specific value is present; setting it to `false` clears that value.
    ///
    /// - Parameter value: The value to look for.
    /// - Returns: `true` when the optional holds `value`.
    subscript(isPresenting value: Wrapped) -> Bool {
        get { self == value }
        set { if !newValue, self == value { self = nil } }
    }
}

nonisolated extension Bool {
    /// An empty value while `true` and `nil` while `false`; setting it stores whether a value is present.
    var presented: Void? {
        get { self ? () : nil }
        set { self = newValue != nil }
    }
}
