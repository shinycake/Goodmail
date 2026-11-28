import SwiftUI
import WidgetKit

#if canImport(MailIntents)
    import MailIntents
    import MailStore
#endif

@main
struct WidgetsBundle: WidgetBundle {
    init() {
        #if canImport(MailIntents)
            // The database opens off the main actor; each intent waits for it.
            registerMailIntentsHost {
                guard let database = await WidgetDatabase.opening.value else { throw WidgetHostError.noDatabase }
                return WidgetHost(database: database)
            }
        #endif
    }

    var body: some Widget {
        InboxWidget()
        #if canImport(MailIntents)
            NewMessageControl()
        #endif
    }
}
