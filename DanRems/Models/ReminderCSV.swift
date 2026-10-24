import EventKit
import Foundation

/// Renders reminders as a CSV spreadsheet for the synced OneDrive file. Pure
/// text assembly, like `ReminderExport` — fetching and writing live in
/// `SheetSync`.
///
/// The output depends only on the reminders, never on when it was made: both
/// the iPhone and the Mac write the same file, and identical input has to
/// produce identical bytes so an unchanged sheet is never rewritten.
enum ReminderCSV {
    static let header = [
        "List", "Title", "Due", "Status", "Completed On", "Priority",
        "Points", "Repeats", "In Progress", "Fun", "Notes", "Questions", "ID",
    ]

    /// Open reminders first, soonest due at the top; then completed ones,
    /// most recently finished first. Ties fall back to title and then ID so the
    /// order is stable from one sync to the next.
    static func csv(for items: [ReminderItem]) -> String {
        let open = items.filter { !$0.isCompleted }.sorted { a, b in
            if a.dueDate != b.dueDate { return (a.dueDate ?? .distantFuture) < (b.dueDate ?? .distantFuture) }
            if a.title != b.title { return a.title < b.title }
            return a.id < b.id
        }
        let done = items.filter(\.isCompleted).sorted { a, b in
            if a.completionDate != b.completionDate {
                return (a.completionDate ?? .distantPast) > (b.completionDate ?? .distantPast)
            }
            if a.title != b.title { return a.title < b.title }
            return a.id < b.id
        }

        let rows = [header] + (open + done).map(row(for:))
        // CRLF per RFC 4180 — what Excel expects, and it keeps the line breaks
        // inside quoted notes distinguishable from row breaks.
        return rows.map { $0.map(escape).joined(separator: ",") }.joined(separator: "\r\n") + "\r\n"
    }

    private static func row(for item: ReminderItem) -> [String] {
        [
            item.listName,
            item.title,
            item.dueDate.map(formatDue) ?? "",
            item.isCompleted ? "Done" : "Open",
            item.completionDate.map(formatDateTime) ?? "",
            priorityText(item.priority),
            item.storyPoints?.label ?? "",
            repeatsText(item.recurrenceFrequency, interval: item.recurrenceInterval),
            item.isInProgress ? "Yes" : "",
            item.isFun ? "Yes" : "",
            item.displayNotes ?? "",
            item.questions.joined(separator: "\n"),
            item.id,
        ]
    }

    // MARK: - Pieces

    /// "2026-10-09", or "2026-10-09 14:30" when the reminder has a time — both
    /// forms Excel recognizes as dates. A due time of exactly midnight reads as
    /// date-only, since `ReminderItem` doesn't record whether a time was set.
    private static func formatDue(_ date: Date) -> String {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        return parts.hour == 0 && parts.minute == 0 ? formatDate(date) : formatDateTime(date)
    }

    /// Built from local calendar components rather than an ISO formatter,
    /// which would render in UTC and push evening reminders onto the next day.
    private static func formatDate(_ date: Date) -> String {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    private static func formatDateTime(_ date: Date) -> String {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        return formatDate(date) + String(format: " %02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }

    /// EventKit's 1–9 scale folded the way Apple Reminders shows it.
    private static func priorityText(_ priority: Int) -> String {
        switch priority {
        case 1...4: "High"
        case 5: "Medium"
        case 6...9: "Low"
        default: ""
        }
    }

    private static func repeatsText(_ frequency: EKRecurrenceFrequency?, interval: Int?) -> String {
        guard let frequency else { return "" }
        let n = max(interval ?? 1, 1)
        let (single, unit) = switch frequency {
        case .daily: ("Daily", "days")
        case .weekly: ("Weekly", "weeks")
        case .monthly: ("Monthly", "months")
        case .yearly: ("Yearly", "years")
        @unknown default: ("Repeats", "")
        }
        return n == 1 || unit.isEmpty ? single : "Every \(n) \(unit)"
    }

    /// Quotes a field only when it has to be: commas, quotes, or line breaks.
    private static func escape(_ field: String) -> String {
        guard field.contains(where: { $0 == "," || $0 == "\"" || $0.isNewline }) else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
