import MailCore
import SwiftUI

/// One condition's controls: what it reads, how it compares, and the value.
struct ConditionEditorRow: View {
    @Binding var kind: ConditionDraft.Kind
    let labelNames: [String]

    var body: some View {
        VStack(alignment: .leading) {
            switch kind {
            case .text(let field, let test, let value):
                HStack {
                    menu(MailCore.TextField.allCases, \.ruleTitle, field) { kind = .text($0, test, value) }
                    menu(ConditionDraft.TextTest.allCases, \.title, test) { kind = .text(field, $0, value) }
                }
                if test.takesValue {
                    SwiftUI.TextField(
                        text: Binding(get: { value }, set: { kind = .text(field, test, $0) }),
                        prompt: Text(
                            "Value", tableName: "Rules", bundle: .module, comment: "Placeholder: text to match")
                    ) {
                        Text("Value", tableName: "Rules", bundle: .module, comment: "Placeholder: text to match")
                    }
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                }
            case .number(let field, let test, let value):
                HStack {
                    menu(NumberField.allCases, \.ruleTitle, field) { kind = .number($0, test, value) }
                    menu(ConditionDraft.NumberTest.allCases, \.title, test) { kind = .number(field, $0, value) }
                }
                SwiftUI.TextField(
                    text: Binding(get: { value }, set: { kind = .number(field, test, $0) }),
                    prompt: Text("Number", tableName: "Rules", bundle: .module, comment: "Placeholder: a number")
                ) {
                    Text("Number", tableName: "Rules", bundle: .module, comment: "Placeholder: a number")
                }
                .keyboardType(.decimalPad)
            case .flag(let flag, let value):
                HStack {
                    menu(MailFlag.allCases, \.ruleTitle, flag) { kind = .flag($0, value) }
                    Picker(selection: Binding(get: { value }, set: { kind = .flag(flag, $0) })) {
                        Text("Yes", tableName: "Rules", bundle: .module, comment: "The status holds").tag(true)
                        Text("No", tableName: "Rules", bundle: .module, comment: "The status doesn't hold").tag(false)
                    } label: {
                        Text("Holds", tableName: "Rules", bundle: .module, comment: "Whether the status holds")
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .fixedSize()
                }
            case .weekdays(let days):
                Text("Day of the Week", tableName: "Rules", bundle: .module, comment: "Condition: weekday")
                WeekdayPicker(days: Binding(get: { days }, set: { kind = .weekdays($0) }))
            case .timeOfDay(let from, let to):
                Text(
                    "Between", tableName: "Rules", bundle: .module,
                    comment: "Condition: received between two times; it may cross midnight")
                HStack {
                    TimeOfDayPicker(time: Binding(get: { from }, set: { kind = .timeOfDay(from: $0, to: to) }))
                    Text(verbatim: "–")
                    TimeOfDayPicker(time: Binding(get: { to }, set: { kind = .timeOfDay(from: from, to: $0) }))
                }
            case .receivedWithin(let amount, let unit):
                Text(
                    "Received Within the Last", tableName: "Rules", bundle: .module,
                    comment: "Condition: received at most this long ago")
                LengthField(
                    amount: Binding(get: { amount }, set: { kind = .receivedWithin($0, unit) }),
                    unit: Binding(get: { unit }, set: { kind = .receivedWithin(amount, $0) }))
            case .label(let name):
                Text("Has Label", tableName: "Rules", bundle: .module, comment: "Condition: carries a label")
                LabelNameField(name: Binding(get: { name }, set: { kind = .label($0) }), labelNames: labelNames)
            }
        }
    }

    /// A menu picking one of `choices`, each shown by `title`.
    private func menu<Choice: Hashable>(
        _ choices: [Choice], _ title: KeyPath<Choice, String>, _ selection: Choice,
        set: @escaping @MainActor (Choice) -> Void
    ) -> some View {
        Picker(selection: Binding(get: { selection }, set: set)) {
            ForEach(choices, id: \.self) { Text($0[keyPath: title]).tag($0) }
        } label: {
            Text(selection[keyPath: title])
        }
        .labelsHidden()
        .pickerStyle(.menu)
    }
}

/// One action, with its label, length or keyword when it takes one.
struct ActionEditorRow: View {
    @Binding var kind: ActionDraft.Kind
    let labelNames: [String]

    var body: some View {
        VStack(alignment: .leading) {
            Label(kind.title, systemImage: kind.symbol)
            switch kind {
            case .move(let label):
                LabelNameField(
                    name: Binding(get: { label }, set: { kind = .move(toLabel: $0) }), labelNames: labelNames)
            case .addLabel(let label):
                LabelNameField(name: Binding(get: { label }, set: { kind = .addLabel($0) }), labelNames: labelNames)
            case .snooze(let amount, let unit):
                LengthField(
                    amount: Binding(get: { amount }, set: { kind = .snooze($0, unit) }),
                    unit: Binding(get: { unit }, set: { kind = .snooze(amount, $0) }))
            case .notify(let keyword):
                SwiftUI.TextField(
                    text: Binding(get: { keyword }, set: { kind = .notify(keyword: $0) }),
                    prompt: Text(
                        "Keyword", tableName: "Rules", bundle: .module,
                        comment: "Placeholder: the notification's title, which a Shortcuts automation watches for")
                ) {
                    Text(
                        "Keyword", tableName: "Rules", bundle: .module,
                        comment: "Placeholder: the notification's title, which a Shortcuts automation watches for")
                }
            case .markRead, .star, .markImportant, .archive, .trash, .reportSpam, .pin, .mute:
                EmptyView()
            }
        }
    }
}

/// The days of the week as toggles, in the order the reader's calendar starts its week.
private struct WeekdayPicker: View {
    @Binding var days: Set<Weekday>
    @Environment(\.calendar) private var calendar

    var body: some View {
        HStack {
            ForEach(ordered, id: \.self) { day in
                let isOn = days.contains(day)
                Button {
                    if isOn { days.remove(day) } else { days.insert(day) }
                } label: {
                    Text(verbatim: calendar.veryShortStandaloneWeekdaySymbols[day.rawValue - 1])
                        .font(.footnote.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 32)
                        .background(isOn ? Color.accentColor : Color(uiColor: .tertiarySystemFill), in: .circle)
                        .foregroundStyle(isOn ? Color.white : Color.primary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(verbatim: calendar.standaloneWeekdaySymbols[day.rawValue - 1]))
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
    }

    private var ordered: [Weekday] {
        let all = Weekday.allCases
        let start = calendar.firstWeekday - 1
        return Array(all[start...] + all[..<start])
    }
}

/// An hour and minute, with the system's time wheel.
private struct TimeOfDayPicker: View {
    @Binding var time: TimeOfDay
    @Environment(\.calendar) private var calendar

    var body: some View {
        DatePicker(selection: date, displayedComponents: .hourAndMinute) {
            EmptyView()
        }
        .labelsHidden()
    }

    private var date: Binding<Date> {
        Binding {
            calendar.date(bySettingHour: time.hour, minute: time.minute, second: 0, of: .now) ?? .now
        } set: {
            let parts = calendar.dateComponents([.hour, .minute], from: $0)
            time = TimeOfDay(hour: parts.hour ?? 0, minute: parts.minute ?? 0)
        }
    }
}
