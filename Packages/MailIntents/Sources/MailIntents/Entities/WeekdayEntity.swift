public import AppIntents
import MailCore

/// The day of the week mail arrived on, for Find and Filter.
public enum WeekdayEntity: Int, AppEnum {
    case sunday = 1
    case monday, tuesday, wednesday, thursday, friday, saturday

    public static let typeDisplayRepresentation: TypeDisplayRepresentation = "Day of the Week"

    public static let caseDisplayRepresentations: [WeekdayEntity: DisplayRepresentation] = [
        .sunday: "Sunday",
        .monday: "Monday",
        .tuesday: "Tuesday",
        .wednesday: "Wednesday",
        .thursday: "Thursday",
        .friday: "Friday",
        .saturday: "Saturday",
    ]

    /// The day `Calendar` numbers `weekday`, from 1 for Sunday.
    init(_ weekday: Int) {
        self = WeekdayEntity(rawValue: weekday) ?? .sunday
    }

    var weekday: Weekday { Weekday(rawValue: rawValue) ?? .sunday }
}
