import EventKit
import SwiftUI

struct ReminderDetailView: View {
    @Environment(ReminderService.self) private var service
    @Environment(\.dismiss) private var dismiss
    let reminderID: String

    @State private var showDeleteConfirmation = false
    @State private var errorMessage: String?
    @State private var toastMessage: String?
    @State private var loaded = false

    // Editable state
    @State private var title = ""
    @State private var selectedCalendarIndex = 0
    @State private var hasDueDate = true
    @State private var dueDate = Date()
    @State private var includeTime = false
    @State private var notes = ""
    @State private var priority = 0
    @State private var recurrenceType: RecurrenceType = .none
    @State private var recurrenceInterval = 1
    @State private var showHistory = false
    @State private var completionHistory: [Date] = []

    private var item: ReminderItem? {
        service.getReminder(identifier: reminderID)
    }

    private var nextDueDate: Date? {
        guard recurrenceType != .none, hasDueDate else { return nil }
        let cal = Calendar.current
        return switch recurrenceType {
        case .none: nil
        case .daily: cal.date(byAdding: .day, value: recurrenceInterval, to: dueDate)
        case .weekly: cal.date(byAdding: .weekOfYear, value: recurrenceInterval, to: dueDate)
        case .monthly: cal.date(byAdding: .month, value: recurrenceInterval, to: dueDate)
        case .yearly: cal.date(byAdding: .year, value: recurrenceInterval, to: dueDate)
        }
    }

    private var hasChanges: Bool {
        guard let item else { return false }
        let calendarChanged = service.calendars.indices.contains(selectedCalendarIndex)
            && service.calendars[selectedCalendarIndex].calendarIdentifier != item.listIdentifier
        let dueDateChanged: Bool = {
            if hasDueDate != (item.dueDate != nil) { return true }
            if hasDueDate, let orig = item.dueDate, dueDate != orig { return true }
            return false
        }()
        let origRecurrence = item.recurrenceFrequency.map { RecurrenceType.from($0) } ?? .none
        let origInterval = item.recurrenceInterval ?? 1
        return title != item.title
            || calendarChanged
            || dueDateChanged
            || notes != (item.notes ?? "")
            || priority != item.priority
            || recurrenceType != origRecurrence
            || recurrenceInterval != origInterval
    }

    var body: some View {
        Group {
            if item != nil {
                form
            } else {
                ContentUnavailableView(
                    "Not Found",
                    systemImage: "questionmark.circle",
                    description: Text("This reminder may have been deleted.")
                )
            }
        }
        .navigationTitle(title.isEmpty ? "Reminder" : title)
        .toolbar {
            if item != nil {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!hasChanges || title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .confirmationDialog(
            "Delete Reminder",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                do {
                    try service.deleteReminder(identifier: reminderID)
                    dismiss()
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to delete this reminder? This cannot be undone.")
        }
        .alert("Error", isPresented: .init(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") { errorMessage = nil }
        } message: {
            if let errorMessage { Text(errorMessage) }
        }
        .overlay(alignment: .bottom) {
            if let toastMessage {
                Text(toastMessage)
                    .font(.subheadline)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.thinMaterial, in: Capsule())
                    .shadow(radius: 4)
                    .padding(.bottom, 32)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut, value: toastMessage)
        .onAppear { if !loaded { loadState(); loaded = true } }
    }

    // MARK: - Form

    private var form: some View {
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
                    if let next = nextDueDate {
                        LabeledContent("Next Due") {
                            Text(next, format: .dateTime.month(.abbreviated).day().year())
                        }
                    }
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

            Section {
                if let item {
                    Button {
                        completeItem(item)
                    } label: {
                        Label(
                            item.isCompleted ? "Mark Incomplete" : "Mark Complete",
                            systemImage: item.isCompleted ? "circle" : "checkmark.circle"
                        )
                    }
                }

                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    Label("Delete Reminder", systemImage: "trash")
                }
            }

            Section {
                Toggle("Completion History", isOn: $showHistory)
                    .onChange(of: showHistory) { _, newValue in
                        if newValue, let item {
                            Task {
                                completionHistory = await service.fetchCompletionHistory(
                                    title: item.title, calendarIdentifier: item.listIdentifier
                                )
                            }
                        }
                    }

                if showHistory {
                    if completionHistory.isEmpty {
                        Text("No completions found")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(completionHistory, id: \.self) { date in
                            Text(date.formatted(.dateTime.month(.abbreviated).day().year().hour().minute()))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private func loadState() {
        guard let item = service.getReminder(identifier: reminderID) else { return }

        title = item.title
        notes = item.notes ?? ""
        priority = item.priority
        if let date = item.dueDate {
            hasDueDate = true
            dueDate = date
            let comps = Calendar.current.dateComponents([.hour, .minute], from: date)
            includeTime = (comps.hour != 0 || comps.minute != 0)
        } else {
            hasDueDate = false
        }
        if let calIndex = service.calendars.firstIndex(where: { $0.calendarIdentifier == item.listIdentifier }) {
            selectedCalendarIndex = calIndex
        }
        if let freq = item.recurrenceFrequency, let interval = item.recurrenceInterval {
            recurrenceType = RecurrenceType.from(freq)
            recurrenceInterval = interval
        } else {
            recurrenceType = .none
            recurrenceInterval = 1
        }
    }

    private func save() {
        let calendar = service.calendars[selectedCalendarIndex]
        let date = hasDueDate ? dueDate : nil
        let noteText = notes.isEmpty ? nil : notes
        let rule = recurrenceType.rule(interval: recurrenceInterval)

        do {
            try service.updateReminder(
                identifier: reminderID, title: title, calendar: calendar,
                dueDate: date, includeTime: includeTime,
                notes: noteText, priority: priority, recurrenceRule: rule
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func completeItem(_ item: ReminderItem) {
        if !item.isCompleted {
            do {
                let nextDate = try service.completeReminder(identifier: item.id)
                if let nextDate {
                    showToast("\(item.title) — next due \(nextDate.formatted(.dateTime.month(.abbreviated).day().year()))")
                } else {
                    showToast("\(item.title) completed")
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        } else {
            try? service.toggleComplete(identifier: item.id)
        }
    }

    private func showToast(_ message: String) {
        toastMessage = message
        Task {
            try? await Task.sleep(for: .seconds(2.5))
            toastMessage = nil
        }
    }
}
