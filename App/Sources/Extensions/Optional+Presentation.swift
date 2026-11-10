nonisolated extension Optional {
    /// Whether a value is present; setting it to `false` clears the value.
    var isPresented: Bool {
        get { self != nil }
        set { if !newValue { self = nil } }
    }
}
