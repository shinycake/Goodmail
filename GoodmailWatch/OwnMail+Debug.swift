#if DEBUG
    import Foundation
    import MailCore
    import MailWrist
    import MailWristHost
    import OSLog

    extension OwnMail {
        /// `-GoodmailWristIndependent YES` has the watch read Gmail and Outlook itself whatever the iPhone's switch
        /// says.
        nonisolated static var forcesIndependence: Bool {
            UserDefaults.standard.bool(forKey: "GoodmailWristIndependent")
        }

        /// `-GoodmailWristSeedSignIns <path>` puts sign-ins on the watch, as iCloud Keychain would, for a simulator,
        /// which has none. The file is a JSON array of `{"account": "<id>", "service": "gmail", "refreshToken": "…"}`
        /// for accounts the paired iPhone has. It stays on the Mac, so no token is passed on the command line.
        nonisolated static func seedSignInsIfRequested(into signIns: WristSignIns) {
            guard let path = UserDefaults.standard.string(forKey: "GoodmailWristSeedSignIns") else { return }
            do {
                let seeds = try JSONDecoder().decode([Seed].self, from: Data(contentsOf: URL(filePath: path)))
                for seed in seeds {
                    let account = WristAccount(
                        id: AccountID(rawValue: seed.account), address: "", color: .blue, unread: 0,
                        service: seed.service)
                    try signIns.keepOnDevice(refreshToken: seed.refreshToken, for: account)
                }
            } catch {
                log.error("Couldn't seed the watch's sign-ins: \(error, privacy: .private)")
            }
        }
    }

    private nonisolated struct Seed: Decodable {
        let account: String
        let service: MailService
        let refreshToken: String
    }
#endif
