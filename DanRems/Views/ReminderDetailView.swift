import EventKit
import SwiftUI

struct ReminderDetailView: View {
    @Environment(ReminderService.self) private var service
    @Environment(\.dismiss) private var dismiss
    let reminderID: String

    @State private var showEdit = false
    @State private var showDeleteConfirmation = false
    @State private var errorMessage: String?

    private var item: ReminderItem? {
        service.getReminder(identifier: reminderID)
    }

    var body: some View {
        Group {
            if let item {
                List {
                    Section("Details") {
                        LabeledContent("Title", value: item.title)

                        LabeledContent("List", value: item.listName)

                        if let dueDate = item.dueDate {
                            LabeledContent("Due Date") {
                                Text(dueDate, format: .dateTime)
                            }
                        }

                        if item.priority > 0 {
                            LabeledContent("Priority", value: priorityLabel(item.priority))
                        }

                        LabeledContent("Status", value: item.isCompleted ? "Completed" : "Incomplete")
                    }

                    if let notes = item.notes, !notes.isEmpty {
                        Section("Notes") {
                            Text(notes)
                        }
                    }

                    if let freq = item.recurrenceFrequency, let interval = item.recurrenceInterval {
                        Section("Recurrence") {
                            Text(recurrenceDescription(freq, interval: interval))
                        }
                    }

                    Section {
                        Button {
                            try? service.toggleComplete(identifier: item.id)
                        } label: {
                            Label(
                                item.isCompleted ? "Mark Incomplete" : "Mark Complete",
                                systemImage: item.isCompleted ? "circle" : "checkmark.circle"
                            )
                        }

                        Button(role: .destructive) {
                            showDeleteConfirmation = true
                        } label: {
                            Label("Delete Reminder", systemImage: "trash")
                        }
                    }
                }
            } else {
                ContentUnavailableView(
                    "Not Found",
                    systemImage: "questionmark.circle",
                    description: Text("This reminder may have been deleted.")
                )
            }
        }
        .navigationTitle(item?.title ?? "Reminder")
        .toolbar {
            if item != nil {
                Button("Edit") { showEdit = true }
            }
        }
        .sheet(isPresented: $showEdit) {
            ReminderEditView(mode: .edit(reminderID))
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
    }

    private func priorityLabel(_ priority: Int) -> String {
        switch priority {
        case 1: "High"
        case 5: "Medium"
        case 9: "Low"
        default: "None"
        }
    }

    private func recurrenceDescription(_ frequency: EKRecurrenceFrequency, interval: Int) -> String {
        let freq = switch frequency {
        case .daily: "day"
        case .weekly: "week"
        case .monthly: "month"
        case .yearly: "year"
        @unknown default: "period"
        }
        if interval == 1 {
            return "Every \(freq)"
        }
        return "Every \(interval) \(freq)s"
    }
}
