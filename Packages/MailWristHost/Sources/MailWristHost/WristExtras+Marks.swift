public import MailCore
public import MailStore
public import MailWrist

extension WristExtras {
    /// The extras of this device's `marks`, carrying only the signatures the service of each of `accounts` doesn't
    /// keep itself.
    public init(_ marks: DeviceMarks, accounts: [Account], independence: WristIndependence) {
        let kept = Set(accounts.filter(\.service.keepsSignature).map(\.id))
        let focus: Set<AccountID>? =
            switch marks.focus {
            case .everyAccount: nil
            case .accounts(let accounts): accounts
            }
        self.init(
            pinned: marks.pinned, asleep: marks.asleep, muted: marks.muted, focus: focus,
            signatures: marks.signatures.filter { !kept.contains($0.key) }, independence: independence)
    }
}

extension MailService {
    /// Whether the service keeps the account's signature, so a device that reads it itself finds it there. Gmail's
    /// send-as settings do; the others' signatures are set on the iPhone.
    fileprivate var keepsSignature: Bool {
        switch self {
        case .gmail: true
        case .outlook, .icloud, .imap: false
        }
    }
}
