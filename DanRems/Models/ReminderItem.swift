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
    var completionDate: Date?
    var recurrenceFrequency: EKRecurrenceFrequency?
    var recurrenceInterval: Int?
    var storyPoints: StoryPoints?
    var isInProgress: Bool
    var isFun: Bool

    /// Notes with every tag and `#q` question removed — what every editor and
    /// label shows, since the tags are storage rather than something Dan
    /// typed, and questions are edited in their own section.
    var displayNotes: String? {
        ReminderNotes.strippingTagsAndQuestions(from: notes)
    }

    /// The `#q` questions asked when this reminder is completed.
    var questions: [String] {
        ReminderNotes.questions(in: notes)
    }

    /// The answer each question got last time, keyed by question, for showing
    /// next to it. Empty when nothing has been logged yet.
    var lastAnswers: [String: String] {
        let questions = questions
        guard let answers = ReminderNotes.lastAnswers(in: notes, count: questions.count) else { return [:] }
        return Dictionary(
            zip(questions, answers).filter { !$0.1.isEmpty },
            uniquingKeysWith: { first, _ in first }
        )
    }

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

    /// EventKit doesn't expose the Reminders app's dedicated URL field, so we
    /// scan notes for links instead — see https://developer.apple.com/forums/thread/739541
    var noteURLs: [URL] {
        guard let notes, !notes.isEmpty,
              let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        else { return [] }
        let range = NSRange(notes.startIndex..., in: notes)
        return detector.matches(in: notes, range: range).compactMap(\.url)
    }

    static func safeFrom(_ reminder: EKReminder) -> ReminderItem? {
        // Guard against reminders with missing essential data
        guard !reminder.calendarItemIdentifier.isEmpty else { return nil }
        return from(reminder)
    }

    static func from(_ reminder: EKReminder) -> ReminderItem {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0
        let uiColor = UIColor(cgColor: reminder.calendar.cgColor)
        // Convert to sRGB to ensure getRed works regardless of source color space
        let srgbColor = uiColor.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
        if !srgbColor.getRed(&r, green: &g, blue: &b, alpha: nil) {
            // Fallback for non-RGB color spaces (grayscale, etc.)
            var white: CGFloat = 0
            srgbColor.getWhite(&white, alpha: nil)
            r = white; g = white; b = white
        }

        var dueDate: Date?
        if let components = reminder.dueDateComponents {
            // Ensure we have a calendar for date conversion
            var comps = components
            if comps.calendar == nil {
                comps.calendar = Calendar.current
            }
            dueDate = comps.date
        }

        let rule = reminder.recurrenceRules?.first
        return ReminderItem(
            id: reminder.calendarItemIdentifier,
            title: reminder.title ?? "",
            notes: reminder.notes,
            dueDate: dueDate,
            isCompleted: reminder.isCompleted,
            priority: reminder.priority,
            listName: reminder.calendar.title,
            listIdentifier: reminder.calendar.calendarIdentifier,
            listColorRed: r,
            listColorGreen: g,
            listColorBlue: b,
            completionDate: reminder.completionDate,
            recurrenceFrequency: rule?.frequency,
            recurrenceInterval: rule?.interval,
            storyPoints: StoryPoints.parse(from: reminder.notes),
            isInProgress: ReminderNotes.isInProgress(reminder.notes),
            isFun: ReminderNotes.isFun(reminder.notes)
        )
    }

    static func == (lhs: ReminderItem, rhs: ReminderItem) -> Bool {
        lhs.id == rhs.id &&
        lhs.title == rhs.title &&
        lhs.notes == rhs.notes &&
        lhs.dueDate == rhs.dueDate &&
        lhs.isCompleted == rhs.isCompleted &&
        lhs.priority == rhs.priority &&
        lhs.listIdentifier == rhs.listIdentifier &&
        lhs.storyPoints == rhs.storyPoints &&
        lhs.isInProgress == rhs.isInProgress &&
        lhs.isFun == rhs.isFun
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
