import Foundation

/// Attribute lookups without the out-pointers of `NSAttributedString`'s own, which strict memory safety marks unsafe.
/// The screens use these.
nonisolated extension NSAttributedString {
    /// The attributes of the character at `location`.
    func attributes(at location: Int) -> [Key: Any] {
        // Unsafe because the range is an out-pointer. Safe: it's nil, so nothing is written.
        unsafe attributes(at: location, effectiveRange: nil)
    }

    /// The value of `key` for the character at `location`.
    func attribute(_ key: Key, at location: Int) -> Any? {
        // Unsafe because the range is an out-pointer. Safe: it's nil, so nothing is written.
        unsafe attribute(key, at: location, effectiveRange: nil)
    }

    /// The value of `key` for the character at `location`, and the longest range within `limit` that has it.
    func attribute(_ key: Key, at location: Int, longestIn limit: NSRange) -> (value: Any?, range: NSRange) {
        var longest = NSRange()
        // Unsafe because the range is an out-pointer. Safe: it points at a local that outlives the call.
        let value = unsafe attribute(key, at: location, longestEffectiveRange: &longest, in: limit)
        return (value, longest)
    }

    /// Calls `body` with each run of identical attributes in `range`, in order.
    func forEachRun(in range: NSRange, _ body: ([Key: Any], NSRange) -> Void) {
        // Unsafe because the closure is handed a stop pointer. Safe: it's never touched.
        unsafe enumerateAttributes(in: range) { attributes, run, _ in body(attributes, run) }
    }
}
