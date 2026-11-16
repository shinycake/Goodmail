/// How far removing an account reaches when this device shares its accounts with the reader's other devices.
public enum AccountRemoval: Sendable {
    /// Off this device; the other devices keep it, and this one doesn't take it back on its own.
    case thisDevice
    /// Off every device that shares accounts, with its shared sign-in.
    case everyDevice
}
