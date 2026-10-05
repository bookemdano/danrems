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
        includeNotes: Bool = true,
        listNames: [String] = [],
        includeContract: Bool = true
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
            lines.append("## \(group.title)\(ReminderTally(group.items).exportSuffix)")
            for item in group.items {
                lines.append(bullet(for: item))
                if includeNotes, let notes = item.displayNotes {
                    for line in notes.split(separator: "\n", omittingEmptySubsequences: true) {
                        lines.append("    - note: \(line.trimmingCharacters(in: .whitespaces))")
                    }
                }
                if includeNotes {
                    for question in item.questions {
                        lines.append("    - question: \(question)")
                    }
                }
            }
            lines.append("")
        }

        if includeContract {
            lines.append(contract(generatedAt: generatedAt, listNames: listNames))
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
        if let points = ReminderTally(open).pointsText {
            parts.append("\(points) points still open")
        }
        let done = items.count - open.count
        if done > 0 {
            parts.append("\(done) completed")
        }
        let unsized = open.filter { $0.storyPoints == nil }.count
        if unsized > 0 {
            parts.append("\(unsized) not yet sized")
        }
        return parts.joined(separator: " · ")
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
        if item.isFun { facts.append("fun") }
        if let recurrence = recurrenceText(item) { facts.append(recurrence) }
        if item.isCompleted, let completed = item.completionDate {
            facts.append("completed \(completed.formatted(.dateTime.month(.abbreviated).day().hour().minute()))")
        }
        return "- [\(item.isCompleted ? "x" : " ")] (\(ReminderRef.ref(for: item))) \(item.title) — \(facts.joined(separator: " · "))"
    }

    // MARK: - The reply contract

    /// The instructions that travel with the export, telling the model exactly
    /// what JSON `ReminderPlan` will accept.
    ///
    /// Shipping the contract inside the export is what makes the round trip one
    /// step for the user: paste the reminders, say what you want, and the reply
    /// is already in the shape DanRems can apply — no need to re-explain the
    /// format, or to keep a prompt around. The closing paragraph spells out what
    /// a plan *can't* do, because a model told only what's possible will happily
    /// invent a `"title"` or a `"delete"` field.
    private static func contract(generatedAt: Date, listNames: [String]) -> String {
        let lists = listNames.isEmpty
            ? "the exact name of a list that already exists"
            : "the exact name of an existing list — \(listNames.joined(separator: ", "))"

        return """
        ---

        ## Sending a plan back to DanRems

        DanRems can apply a plan from the clipboard. Reply with one JSON object \
        in a ```json fence; copy the reply and tap Paste Plan in DanRems.

        ```json
        {
          "summary": "one line on what you changed and why",
          "changes": [
            {
              "ref": "\(sampleRef)",
              "due": "\(isoDay(exampleDueDate(from: generatedAt)))",
              "points": 2,
              "wip": true,
              "fun": false,
              "list": "\(listNames.first ?? "Home")",
              "why": "short reason, shown in the preview"
            }
          ]
        }
        ```

        - `ref` — required, copied exactly from the parentheses beside a reminder above.
        - Every other field is optional. Include only what should change; whatever \
        you leave out stays exactly as it is.
        - `due` — a calendar day, `YYYY-MM-DD`. Today is \(isoDay(generatedAt)). The \
        reminder keeps whatever time of day it already had.
        - `points` — size from 0.1 to 100, Fibonacci-style: 0.5, 1, 2, 3, 5, 8, 13.
        - `wip` — true if it's started, false to clear.
        - `fun` — true if it's one to look forward to, false to clear.
        - `list` — \(lists).
        - `why` — optional one-liner, shown beside the change in the preview.

        A plan can only reschedule, resize, reflag and refile the reminders listed \
        above. It cannot create, rename, complete or delete a reminder, and it \
        cannot make a new list — say those in prose instead and I'll do them by hand.
        """
    }

    /// A stand-in handle for the example, so the shape of a real `ref` is
    /// obvious without pointing the model at one of the actual reminders.
    private static let sampleRef = "r-ab12cd34"

    /// A date a couple of days out, so the example reads as "some other day"
    /// rather than quietly suggesting that today is where things should land.
    private static func exampleDueDate(from date: Date) -> Date {
        Calendar.current.date(byAdding: .day, value: 2, to: date) ?? date
    }

    private static func isoDay(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
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

}
