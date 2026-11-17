// MailIntents can't build on the Linux cloud build (docs/setup/cloud-builds.md); there the bundle has no control.
#if canImport(MailIntents)
    import AppIntents
    import MailIntents
    import SwiftUI
    import WidgetKit

    /// A Control Center, Lock Screen and Action button control that opens the composer.
    struct NewMessageControl: ControlWidget {
        var body: some ControlWidgetConfiguration {
            StaticControlConfiguration(kind: "NewMessage") {
                ControlWidgetButton(action: NewMessageIntent()) {
                    Label("New Message", systemImage: "square.and.pencil")
                }
            }
            .displayName("New Message")
            .description("Write an email.")
        }
    }
#endif
