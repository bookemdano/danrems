import EventKit
import Foundation

@MainActor
@Observable
final class ReminderService {
    private let eventStore = EKEventStore()

    var reminders: [ReminderItem] = []
    var calendars: [EKCalendar] = []
    var authorizationStatus: EKAuthorizationStatus = .notDetermined
    var errorMessage: String?

    func requestAccess() async {
        do {
            let granted = try await eventStore.requestFullAccessToReminders()
            authorizationStatus = EKEventStore.authorizationStatus(for: .reminder)
            if granted {
                loadCalendars()
                await fetchReminders()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadCalendars() {
        calendars = eventStore.calendars(for: .reminder)
    }

    private struct UncheckedSendableReminders: @unchecked Sendable {
        let reminders: [EKReminder]
    }

    private func fetchReminderItems(matching predicate: NSPredicate) async -> [ReminderItem] {
        let store = eventStore
        let wrapped = await withCheckedContinuation { (continuation: CheckedContinuation<UncheckedSendableReminders, Never>) in
            store.fetchReminders(matching: predicate) { reminders in
                continuation.resume(returning: UncheckedSendableReminders(reminders: reminders ?? []))
            }
        }
        // Map on main actor where EKReminder access is safe
        return wrapped.reminders.compactMap { ReminderItem.safeFrom($0) }
    }

    func fetchReminders() async {
        let endOfToday = Date().endOfDay
        let predicate = eventStore.predicateForIncompleteReminders(
            withDueDateStarting: nil,
            ending: endOfToday,
            calendars: nil
        )
        reminders = await fetchReminderItems(matching: predicate)
    }

    func fetchCompletedToday() async -> [ReminderItem] {
        let startOfToday = Date().startOfDay
        let endOfToday = Date().endOfDay
        let predicate = eventStore.predicateForCompletedReminders(
            withCompletionDateStarting: startOfToday,
            ending: endOfToday,
            calendars: nil
        )
        return await fetchReminderItems(matching: predicate)
    }

    func searchReminders(query: String) async -> [ReminderItem] {
        guard !query.isEmpty else { return [] }
        let lowered = query.lowercased()

        let incompletePredicate = eventStore.predicateForIncompleteReminders(
            withDueDateStarting: nil, ending: nil, calendars: nil
        )
        let completedPredicate = eventStore.predicateForCompletedReminders(
            withCompletionDateStarting: nil, ending: nil, calendars: nil
        )

        let incomplete = await fetchReminderItems(matching: incompletePredicate)
        let completed = await fetchReminderItems(matching: completedPredicate)

        return (incomplete + completed)
            .filter { $0.title.lowercased().contains(lowered) }
    }

    func createReminder(
        title: String,
        calendar: EKCalendar,
        dueDate: Date?,
        includeTime: Bool,
        notes: String?,
        priority: Int,
        recurrenceRule: EKRecurrenceRule?
    ) throws {
        let reminder = EKReminder(eventStore: eventStore)
        reminder.title = title
        reminder.calendar = calendar
        if let dueDate {
            var components: Set<Calendar.Component> = [.year, .month, .day]
            if includeTime {
                components.insert(.hour)
                components.insert(.minute)
            }
            reminder.dueDateComponents = Calendar.current.dateComponents(components, from: dueDate)
        }
        reminder.notes = notes
        reminder.priority = priority
        if let recurrenceRule {
            reminder.addRecurrenceRule(recurrenceRule)
        }
        try eventStore.save(reminder, commit: true)
        Task { await fetchReminders() }
    }

    func updateReminder(
        identifier: String,
        title: String,
        calendar: EKCalendar,
        dueDate: Date?,
        includeTime: Bool,
        notes: String?,
        priority: Int,
        recurrenceRule: EKRecurrenceRule?
    ) throws {
        guard let reminder = eventStore.calendarItem(withIdentifier: identifier) as? EKReminder else {
            throw ReminderError.notFound
        }
        reminder.title = title
        reminder.calendar = calendar
        if let dueDate {
            var components: Set<Calendar.Component> = [.year, .month, .day]
            if includeTime {
                components.insert(.hour)
                components.insert(.minute)
            }
            reminder.dueDateComponents = Calendar.current.dateComponents(components, from: dueDate)
        } else {
            reminder.dueDateComponents = nil
        }
        reminder.notes = notes
        reminder.priority = priority
        if let existing = reminder.recurrenceRules {
            for rule in existing { reminder.removeRecurrenceRule(rule) }
        }
        if let recurrenceRule {
            reminder.addRecurrenceRule(recurrenceRule)
        }
        try eventStore.save(reminder, commit: true)
        Task { await fetchReminders() }
    }

    func toggleComplete(identifier: String) throws {
        guard let reminder = eventStore.calendarItem(withIdentifier: identifier) as? EKReminder else {
            throw ReminderError.notFound
        }
        reminder.isCompleted.toggle()
        try eventStore.save(reminder, commit: true)
        Task { await fetchReminders() }
    }

    func deleteReminder(identifier: String) throws {
        guard let reminder = eventStore.calendarItem(withIdentifier: identifier) as? EKReminder else {
            throw ReminderError.notFound
        }
        try eventStore.remove(reminder, commit: true)
        Task { await fetchReminders() }
    }

    func getReminder(identifier: String) -> ReminderItem? {
        guard let reminder = eventStore.calendarItem(withIdentifier: identifier) as? EKReminder else {
            return nil
        }
        return ReminderItem.from(reminder)
    }
}

enum ReminderError: LocalizedError {
    case notFound

    var errorDescription: String? {
        switch self {
        case .notFound: "Reminder not found. It may have been deleted."
        }
    }
}
