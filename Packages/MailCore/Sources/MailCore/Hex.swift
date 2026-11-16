extension Sequence<UInt8> {
    /// The bytes as lowercase hex, two digits each, as device tokens, digests and secrets are written.
    ///
    /// Not `String(format: "%02x")`, whose C variadic arguments strict memory safety rejects.
    public var lowercaseHex: String {
        map { ($0 < 0x10 ? "0" : "") + String($0, radix: 16) }.joined()
    }
}
