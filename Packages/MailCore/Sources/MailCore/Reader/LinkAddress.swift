/// A link's address as the reader shows it while the pointer is over the link.
public enum LinkAddress {
    /// `address`, or its beginning and its end with an ellipsis between them when it is longer than `limit`
    /// characters. The host leads and the file or query ends, which are what tell a real link from a disguised one.
    public static func shortened(_ address: String, limit: Int = 80) -> String {
        guard address.count > limit else { return address }
        let kept = max(0, limit - 1)
        let head = (kept + 1) / 2
        let tail = kept - head
        return String(address.prefix(head)) + "…" + String(address.suffix(tail))
    }
}
