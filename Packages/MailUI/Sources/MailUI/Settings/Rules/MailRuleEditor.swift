import MailCore
import SwiftUI

/// Adds a rule or changes one, in a sheet over the list: its name, the conditions a new message must meet, what
/// happens to it, and whether later rules still run. Save is on once every value reads.
struct MailRuleEditor: View {
    let labelNames: [String]
    let save: (MailRule) -> Void
    @State private var draft: RuleDraft
    @Environment(\.dismiss) private var dismiss

    init(draft: RuleDraft, labelNames: [String], save: @escaping (MailRule) -> Void) {
        self.labelNames = labelNames
        self.save = save
        // Seeds the fields once, from the rule being changed or a new one.
        _draft = State(initialValue: draft)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SwiftUI.TextField(
                        text: $draft.name,
                        prompt: Text("Name", tableName: "Rules", bundle: .module, comment: "Placeholder: rule name")
                    ) {
                        Text("Name", tableName: "Rules", bundle: .module, comment: "Placeholder: rule name")
                    }
                }
                conditions
                actions
                Section {
                    Toggle(isOn: $draft.stopsOtherRules) {
                        Text(
                            "Stop Other Rules", tableName: "Rules", bundle: .module,
                            comment: "Toggle: rules after this one skip the mail it acted on")
                    }
                } footer: {
                    Text(
                        "When this rule acts on a message, the rules after it leave that message alone.",
                        tableName: "Rules", bundle: .module, comment: "Explains Stop Other Rules")
                }
            }
            .navigationTitle(draft.rule?.name ?? MailRulesView.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(role: .confirm) {
                        guard let rule = draft.rule else { return }
                        save(rule)
                        dismiss()
                    }
                    .disabled(draft.rule == nil)
                }
            }
        }
    }

    private var conditions: some View {
        Section {
            Picker(selection: $draft.joiner) {
                Text("All", tableName: "Rules", bundle: .module, comment: "Every condition must hold")
                    .tag(RuleDraft.Joiner.all)
                Text("Any", tableName: "Rules", bundle: .module, comment: "One condition is enough")
                    .tag(RuleDraft.Joiner.any)
            } label: {
                Text("Match", tableName: "Rules", bundle: .module, comment: "Whether all or any conditions must hold")
            }
            .pickerStyle(.segmented)
            ForEach($draft.conditions) { $condition in
                ConditionEditorRow(kind: $condition.kind, labelNames: labelNames)
            }
            .onDelete { draft.conditions.remove(atOffsets: $0) }
            Menu {
                ForEach(RuleChoices.conditions, id: \.title) { choice in
                    Button {
                        draft.conditions.append(ConditionDraft(choice.kind))
                    } label: {
                        Label(choice.title, systemImage: choice.symbol)
                    }
                }
            } label: {
                Label {
                    Text("Add Condition", tableName: "Rules", bundle: .module, comment: "Adds a condition to a rule")
                } icon: {
                    Image(systemName: "plus.circle.fill")
                }
            }
        } header: {
            Text("When a Message Arrives", tableName: "Rules", bundle: .module, comment: "Header of the conditions")
        }
    }

    private var actions: some View {
        Section {
            ForEach($draft.actions) { $action in
                ActionEditorRow(kind: $action.kind, labelNames: labelNames)
            }
            .onDelete { draft.actions.remove(atOffsets: $0) }
            Menu {
                ForEach(RuleChoices.actions, id: \.title) { kind in
                    Button {
                        draft.actions.append(ActionDraft(kind))
                    } label: {
                        Label(kind.title, systemImage: kind.symbol)
                    }
                }
            } label: {
                Label {
                    Text("Add Action", tableName: "Rules", bundle: .module, comment: "Adds an action to a rule")
                } icon: {
                    Image(systemName: "plus.circle.fill")
                }
            }
        } header: {
            Text("Do", tableName: "Rules", bundle: .module, comment: "Header of the rule's actions")
        }
    }
}

/// A text field for a label's name, with the reader's labels to pick from.
struct LabelNameField: View {
    @Binding var name: String
    let labelNames: [String]

    var body: some View {
        HStack {
            SwiftUI.TextField(
                text: $name,
                prompt: Text("Label Name", tableName: "Rules", bundle: .module, comment: "Placeholder: a label's name")
            ) {
                Text("Label Name", tableName: "Rules", bundle: .module, comment: "Placeholder: a label's name")
            }
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            if !labelNames.isEmpty {
                Menu {
                    ForEach(labelNames, id: \.self) { label in
                        Button(label) { name = label }
                    }
                } label: {
                    Label {
                        Text("Choose Label", tableName: "Rules", bundle: .module, comment: "Picks one of the labels")
                    } icon: {
                        Image(systemName: "tag")
                    }
                    .labelStyle(.iconOnly)
                }
            }
        }
    }
}

/// A length of time: a whole number and its unit.
struct LengthField: View {
    @Binding var amount: Int
    @Binding var unit: TimeUnit

    var body: some View {
        HStack {
            Stepper(value: $amount, in: 1...365) {
                Text(verbatim: "\(amount)").monospacedDigit()
            }
            Picker(selection: $unit) {
                ForEach(TimeUnit.allCases, id: \.self) { Text($0.title).tag($0) }
            } label: {
                Text("Unit", tableName: "Rules", bundle: .module, comment: "Hours, days or weeks")
            }
            .labelsHidden()
            .pickerStyle(.menu)
        }
    }
}
