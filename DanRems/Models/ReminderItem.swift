import EventKit
import SwiftUI
import UIKit

struct ReminderItem: Identifiable, Hashable, Sendable {
    let id: String
    var title: String
    var notes: String?
    var dueDate: Date?
    var isCompleted: Bool
    var priority: Int
    var listName: String
    var listIdentifier: String
    var listColorRed: CGFloat
    var listColorGreen: CGFloat
    var listColorBlue: CGFloat
    var recurrenceFrequency: EKRecurrenceFrequency?
    var recurrenceInterval: Int?

    var isOverdue: Bool {
        guard !isCompleted, let dueDate else { return false }
        return dueDate < Date().startOfDay
    }

    var isDueToday: Bool {
        guard let dueDate else { return false }
        return Calendar.current.isDateInToday(dueDate)
    }

    var listColor: Color {
        Color(red: listColorRed, green: listColorGreen, blue: listColorBlue)
    }

    static func from(_ reminder: EKReminder) -> ReminderItem {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0
        UIColor(cgColor: reminder.calendar.cgColor).getRed(&r, green: &g, blue: &b, alpha: nil)

        let rule = reminder.recurrenceRules?.first
        return ReminderItem(
            id: reminder.calendarItemIdentifier,
            title: reminder.title ?? "",
            notes: reminder.notes,
            dueDate: reminder.dueDateComponents?.date,
            isCompleted: reminder.isCompleted,
            priority: reminder.priority,
            listName: reminder.calendar.title,
            listIdentifier: reminder.calendar.calendarIdentifier,
            listColorRed: r,
            listColorGreen: g,
            listColorBlue: b,
            recurrenceFrequency: rule?.frequency,
            recurrenceInterval: rule?.interval
        )
    }

    static func == (lhs: ReminderItem, rhs: ReminderItem) -> Bool {
        lhs.id == rhs.id &&
        lhs.title == rhs.title &&
        lhs.notes == rhs.notes &&
        lhs.dueDate == rhs.dueDate &&
        lhs.isCompleted == rhs.isCompleted &&
        lhs.priority == rhs.priority &&
        lhs.listIdentifier == rhs.listIdentifier
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
