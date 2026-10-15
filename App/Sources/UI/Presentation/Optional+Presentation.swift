nonisolated extension Optional {
    /// Whether a value is present, so `$value.isPresented` drives a presentation.
    ///
    /// Dismissing the presentation clears the value.
    var isPresented: Bool {
        get { self != nil }
        set { if !newValue { self = nil } }
    }
}
