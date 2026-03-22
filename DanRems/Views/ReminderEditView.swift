import EventKit
import SwiftUI

enum EditMode {
    case create
    case edit(String)
}

struct ReminderEditView: View {
    @Environment(ReminderService.self) private var service
    @Environment(\.dismiss) private var dismiss

    let mode: EditMode

    @State private var title = ""
    @State private var selectedCalendarIndex = 0
    @State private var hasDueDate = false
    @State private var dueDate = Date()
    @State private var includeTime = false
    @State private var notes = ""
    @State private var priority = 0
    @State private var recurrenceType: RecurrenceType = .none
    @State private var recurrenceInterval = 1
    @State private var errorMessage: String?

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    private var navigationTitle: String {
        isEditing ? "Edit Reminder" : "New Reminder"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Basic Info") {
                    TextField("Title", text: $title)

                    if !service.calendars.isEmpty {
                        Picker("List", selection: $selectedCalendarIndex) {
                            ForEach(Array(service.calendars.enumerated()), id: \.offset) { index, cal in
                                Text(cal.title).tag(index)
                            }
                        }
                    }
                }

                Section("Schedule") {
                    Toggle("Due Date", isOn: $hasDueDate)

                    if hasDueDate {
                        DatePicker(
                            "Date",
                            selection: $dueDate,
                            displayedComponents: includeTime ? [.date, .hourAndMinute] : [.date]
                        )
                        Toggle("Include Time", isOn: $includeTime)
                    }
                }

                Section("Recurrence") {
                    Picker("Repeat", selection: $recurrenceType) {
                        ForEach(RecurrenceType.allCases) { type in
                            Text(type.label).tag(type)
                        }
                    }

                    if recurrenceType != .none {
                        Stepper("Every \(recurrenceInterval) \(recurrenceType.unit)\(recurrenceInterval > 1 ? "s" : "")",
                                value: $recurrenceInterval, in: 1...999)
                    }
                }

                Section("Details") {
                    Picker("Priority", selection: $priority) {
                        Text("None").tag(0)
                        Text("Low").tag(9)
                        Text("Medium").tag(5)
                        Text("High").tag(1)
                    }

                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle(navigationTitle)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .alert("Error", isPresented: .init(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK") { errorMessage = nil }
            } message: {
                if let errorMessage { Text(errorMessage) }
            }
            .onAppear { loadExisting() }
        }
    }

    private func loadExisting() {
        guard case .edit(let id) = mode,
              let item = service.getReminder(identifier: id) else { return }

        title = item.title
        notes = item.notes ?? ""
        priority = item.priority
        if let date = item.dueDate {
            hasDueDate = true
            dueDate = date
            let comps = Calendar.current.dateComponents([.hour, .minute], from: date)
            includeTime = (comps.hour != 0 || comps.minute != 0)
        }
        if let calIndex = service.calendars.firstIndex(where: { $0.calendarIdentifier == item.listIdentifier }) {
            selectedCalendarIndex = calIndex
        }
        if let freq = item.recurrenceFrequency, let interval = item.recurrenceInterval {
            recurrenceType = RecurrenceType.from(freq)
            recurrenceInterval = interval
        }
    }

    private func save() {
        let calendar = service.calendars[selectedCalendarIndex]
        let date = hasDueDate ? dueDate : nil
        let noteText = notes.isEmpty ? nil : notes
        let rule = recurrenceType.rule(interval: recurrenceInterval)

        do {
            switch mode {
            case .create:
                try service.createReminder(
                    title: title, calendar: calendar, dueDate: date,
                    includeTime: includeTime, notes: noteText,
                    priority: priority, recurrenceRule: rule
                )
            case .edit(let id):
                try service.updateReminder(
                    identifier: id, title: title, calendar: calendar,
                    dueDate: date, includeTime: includeTime,
                    notes: noteText, priority: priority, recurrenceRule: rule
                )
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

enum RecurrenceType: String, CaseIterable, Identifiable {
    case none, daily, weekly, monthly, yearly

    var id: String { rawValue }

    var label: String {
        switch self {
        case .none: "Never"
        case .daily: "Daily"
        case .weekly: "Weekly"
        case .monthly: "Monthly"
        case .yearly: "Yearly"
        }
    }

    var unit: String {
        switch self {
        case .none: ""
        case .daily: "day"
        case .weekly: "week"
        case .monthly: "month"
        case .yearly: "year"
        }
    }

    var ekFrequency: EKRecurrenceFrequency {
        switch self {
        case .none: .daily
        case .daily: .daily
        case .weekly: .weekly
        case .monthly: .monthly
        case .yearly: .yearly
        }
    }

    func rule(interval: Int) -> EKRecurrenceRule? {
        guard self != .none else { return nil }
        return EKRecurrenceRule(
            recurrenceWith: ekFrequency,
            interval: interval,
            end: nil
        )
    }

    static func from(_ frequency: EKRecurrenceFrequency) -> RecurrenceType {
        switch frequency {
        case .daily: .daily
        case .weekly: .weekly
        case .monthly: .monthly
        case .yearly: .yearly
        @unknown default: .none
        }
    }
}
