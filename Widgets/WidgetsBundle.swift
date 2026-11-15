import SwiftUI
import WidgetKit

#if canImport(MailIntents)
    import MailIntents
#endif

@main
struct WidgetsBundle: WidgetBundle {
    init() {
        #if canImport(MailIntents)
            if let database = WidgetDatabase.shared { WidgetHost(database: database).register() }
        #endif
    }

    var body: some Widget {
        InboxWidget()
    }
}
