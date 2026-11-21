import MailCore

/// The system's login item for the app, behind a protocol so tests can stand in for it.
protocol LoginItemService {
    var status: LoginItemStatus { get }
    func register() throws
    func unregister() throws
    /// Opens System Settings at Login Items, where the reader approves a login item.
    func openSettings()
}

// Only Mac Catalyst has login items: ServiceManagement's SMAppService is unavailable on iOS.
#if targetEnvironment(macCatalyst)
    import ServiceManagement

    /// The app itself as a login item (`SMAppService.mainApp`), which needs no helper bundle.
    struct SystemLoginItem: LoginItemService {
        var status: LoginItemStatus {
            switch SMAppService.mainApp.status {
            case .notRegistered: .notRegistered
            case .enabled: .enabled
            case .requiresApproval: .requiresApproval
            case .notFound: .notFound
            @unknown default: .notFound
            }
        }

        func register() throws { try SMAppService.mainApp.register() }
        func unregister() throws { try SMAppService.mainApp.unregister() }
        func openSettings() { SMAppService.openSystemSettingsLoginItems() }
    }
#endif
