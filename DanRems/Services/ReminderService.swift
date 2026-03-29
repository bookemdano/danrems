import EventKit
import Foundation
import UserNotifications

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
        // Request notification permission for delete alerts
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
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

    func fetchUpcoming(days: Int) async -> [ReminderItem] {
        let startOfTomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date().startOfDay)!
        let endDate = Calendar.current.date(byAdding: .day, value: days, to: Date().endOfDay)!
        let predicate = eventStore.predicateForIncompleteReminders(
            withDueDateStarting: nil,
            ending: endDate,
            calendars: nil
        )
        let all = await fetchReminderItems(matching: predicate)
        return all.filter { item in
            guard let due = item.dueDate else { return false }
            return due >= startOfTomorrow && due <= endDate
        }
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

    /// Completes a reminder and returns the next due date if it's recurring.
    func completeReminder(identifier: String) throws -> Date? {
        guard let reminder = eventStore.calendarItem(withIdentifier: identifier) as? EKReminder else {
            throw ReminderError.notFound
        }

        var nextDueDate: Date?
        if let rule = reminder.recurrenceRules?.first,
           let comps = reminder.dueDateComponents {
            var dueDateComps = comps
            if dueDateComps.calendar == nil { dueDateComps.calendar = Calendar.current }
            if let currentDue = dueDateComps.date {
                let cal = Calendar.current
                nextDueDate = switch rule.frequency {
                case .daily: cal.date(byAdding: .day, value: rule.interval, to: currentDue)
                case .weekly: cal.date(byAdding: .weekOfYear, value: rule.interval, to: currentDue)
                case .monthly: cal.date(byAdding: .month, value: rule.interval, to: currentDue)
                case .yearly: cal.date(byAdding: .year, value: rule.interval, to: currentDue)
                @unknown default: nil
                }
            }
        }

        reminder.isCompleted = true
        try eventStore.save(reminder, commit: true)
        Task { await fetchReminders() }
        return nextDueDate
    }

    func deleteReminder(identifier: String) throws {
        guard let reminder = eventStore.calendarItem(withIdentifier: identifier) as? EKReminder else {
            throw ReminderError.notFound
        }
        let title = reminder.title ?? "Reminder"
        try eventStore.remove(reminder, commit: true)
        sendDeleteNotification(title: title)
        Task { await fetchReminders() }
    }

    private func sendDeleteNotification(title: String) {
        let content = UNMutableNotificationContent()
        content.title = "Reminder Deleted"
        content.body = "Deleted \"\(title)\""
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil // deliver immediately
        )
        UNUserNotificationCenter.current().add(request)
    }

    func moveOverdueToToday() throws {
        let endOfYesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date().startOfDay)!.endOfDay
        let todayComponents = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        for item in reminders where item.isOverdue {
            guard let reminder = eventStore.calendarItem(withIdentifier: item.id) as? EKReminder else { continue }
            var components = reminder.dueDateComponents ?? DateComponents()
            components.year = todayComponents.year
            components.month = todayComponents.month
            components.day = todayComponents.day
            reminder.dueDateComponents = components
            try eventStore.save(reminder, commit: false)
        }
        try eventStore.commit()
        Task { await fetchReminders() }
    }

    func fetchCompletionHistory(title: String, calendarIdentifier: String) async -> [Date] {
        let calendar = calendars.first { $0.calendarIdentifier == calendarIdentifier }
        let cals = calendar.map { [$0] }
        let predicate = eventStore.predicateForCompletedReminders(
            withCompletionDateStarting: nil, ending: nil, calendars: cals
        )
        let items = await fetchReminderItems(matching: predicate)
        return items
            .filter { $0.title == title }
            .compactMap(\.completionDate)
            .sorted(by: >)
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
