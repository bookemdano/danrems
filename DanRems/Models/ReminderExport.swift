import EventKit
import Foundation

/// Renders the reminders currently on screen as Markdown, for pasting into an
/// LLM. Pure text assembly — the caller decides which groups are on screen, so
/// the export always mirrors what the user is actually looking at.
enum ReminderExport {
    /// One on-screen section: the heading as displayed, and its reminders.
    struct Group {
        let title: String
        let items: [ReminderItem]

        init(title: String, items: [ReminderItem]) {
            self.title = title
            self.items = items
        }
    }

    static func markdown(
        groups: [Group],
        generatedAt: Date = Date(),
        includeNotes: Bool = true
    ) -> String {
        let populated = groups.filter { !$0.items.isEmpty }
        let all = populated.flatMap(\.items)

        var lines = ["# DanRems — \(generatedAt.formatted(.dateTime.weekday(.wide).month(.wide).day().year()))"]
        lines.append("")

        guard !all.isEmpty else {
            lines.append("No reminders are currently displayed.")
            return lines.joined(separator: "\n") + "\n"
        }

        lines.append(summary(for: all))
        lines.append("")
        lines.append("Sizes are Fibonacci-style story points (0.1–100): higher means more effort.")
        lines.append("")

        for group in populated {
            lines.append("## \(group.title)\(tally(group.items))")
            for item in group.items {
                lines.append(bullet(for: item))
                if includeNotes, let notes = item.displayNotes {
                    for line in notes.split(separator: "\n", omittingEmptySubsequences: true) {
                        lines.append("    - note: \(line.trimmingCharacters(in: .whitespaces))")
                    }
                }
            }
            lines.append("")
        }

        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
    }

    /// Total reminders across every populated group — what the toast reports.
    static func itemCount(in groups: [Group]) -> Int {
        groups.reduce(0) { $0 + $1.items.count }
    }

    // MARK: - Pieces

    private static func summary(for items: [ReminderItem]) -> String {
        let open = items.filter { !$0.isCompleted }
        var parts = ["\(items.count) reminder\(items.count == 1 ? "" : "s") shown"]
        if let points = format(total(open)) {
            parts.append("\(points) points still open")
        }
        let unsized = open.filter { $0.storyPoints == nil }.count
        if unsized > 0 {
            parts.append("\(unsized) not yet sized")
        }
        return parts.joined(separator: " · ")
    }

    private static func tally(_ items: [ReminderItem]) -> String {
        let count = "\(items.count) item\(items.count == 1 ? "" : "s")"
        guard let points = format(total(items)) else { return " (\(count))" }
        return " (\(count), \(points) pts)"
    }

    private static func bullet(for item: ReminderItem) -> String {
        var facts: [String] = []
        if let points = item.storyPoints { facts.append("\(points.label) pts") }
        if let due = item.dueDate {
            facts.append("due \(due.formatted(.dateTime.month(.abbreviated).day().year()))")
        }
        facts.append(item.listName)
        if let priority = priorityText(item.priority) { facts.append(priority) }
        if item.isInProgress { facts.append("in progress") }
        if let recurrence = recurrenceText(item) { facts.append(recurrence) }
        if item.isCompleted, let completed = item.completionDate {
            facts.append("completed \(completed.formatted(.dateTime.month(.abbreviated).day().hour().minute()))")
        }
        return "- [\(item.isCompleted ? "x" : " ")] \(item.title) — \(facts.joined(separator: " · "))"
    }

    private static func priorityText(_ priority: Int) -> String? {
        switch priority {
        case 1: "high priority"
        case 5: "medium priority"
        case 9: "low priority"
        default: nil
        }
    }

    private static func recurrenceText(_ item: ReminderItem) -> String? {
        guard let frequency = item.recurrenceFrequency else { return nil }
        let interval = item.recurrenceInterval ?? 1
        let unit: String = switch frequency {
        case .daily: "day"
        case .weekly: "week"
        case .monthly: "month"
        case .yearly: "year"
        @unknown default: "period"
        }
        return interval == 1 ? "repeats every \(unit)" : "repeats every \(interval) \(unit)s"
    }

    private static func total(_ items: [ReminderItem]) -> Double {
        items.compactMap(\.storyPoints).reduce(0) { $0 + $1.value }
    }

    /// Nil when nothing in the set carries a size, so callers can omit the
    /// clause entirely rather than printing a misleading "0 pts".
    private static func format(_ total: Double) -> String? {
        total > 0 ? String(format: "%g", total) : nil
    }
}
