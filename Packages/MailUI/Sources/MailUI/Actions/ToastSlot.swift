extension MailActions {
    /// What the toast shows, with the task that ends it on time, which goes with it.
    enum ToastSlot {
        case empty
        case showing(Toast, expiry: Task<Void, Never>)

        var toast: Toast? {
            if case .showing(let toast, _) = self { toast } else { nil }
        }
    }
}
