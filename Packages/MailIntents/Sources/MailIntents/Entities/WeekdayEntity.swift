public import AppIntents
import MailCore

/// The day of the week mail arrived on, for Find and Filter.
public enum WeekdayEntity: Int, AppEnum {
    case sunday = 1
    case monday, tuesday, wednesday, thursday, friday, saturday

    public static let typeDisplayRepresentation: TypeDisplayRepresentation = TypeDisplayRepresentation(
        name: LocalizedStringResource("Day of the Week", table: "ShortcutMail"))

    public static let caseDisplayRepresentations: [WeekdayEntity: DisplayRepresentation] = [
        .sunday: DisplayRepresentation(title: LocalizedStringResource("Sunday", table: "ShortcutMail")),
        .monday: DisplayRepresentation(title: LocalizedStringResource("Monday", table: "ShortcutMail")),
        .tuesday: DisplayRepresentation(title: LocalizedStringResource("Tuesday", table: "ShortcutMail")),
        .wednesday: DisplayRepresentation(title: LocalizedStringResource("Wednesday", table: "ShortcutMail")),
        .thursday: DisplayRepresentation(title: LocalizedStringResource("Thursday", table: "ShortcutMail")),
        .friday: DisplayRepresentation(title: LocalizedStringResource("Friday", table: "ShortcutMail")),
        .saturday: DisplayRepresentation(title: LocalizedStringResource("Saturday", table: "ShortcutMail")),
    ]

    /// The day `Calendar` numbers `weekday`, from 1 for Sunday.
    init(_ weekday: Int) {
        self = WeekdayEntity(rawValue: weekday) ?? .sunday
    }

    var weekday: Weekday { Weekday(rawValue: rawValue) ?? .sunday }
}
