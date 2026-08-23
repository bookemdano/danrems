import Foundation

/// Totals for one group of reminders — shared by the section headers on screen
/// and the Markdown export, so the two always agree.
struct ReminderTally {
    let count: Int
    let completed: Int
    let points: Double

    init(_ items: [ReminderItem]) {
        count = items.count
        completed = items.filter(\.isCompleted).count
        points = items.compactMap(\.storyPoints).reduce(0) { $0 + $1.value }
    }

    /// Nil when nothing in the group carries a size, so callers can drop the
    /// clause rather than print a misleading "0 pts".
    var pointsText: String? {
        points > 0 ? String(format: "%g", points) : nil
    }

    /// "8 pts · 2 done" for a section header. Nil when there's nothing to say.
    var headerDetail: String? {
        detailParts.isEmpty ? nil : detailParts.joined(separator: " · ")
    }

    /// " (2 items, 8 pts)" for a Markdown heading.
    var exportSuffix: String {
        let items = "\(count) item\(count == 1 ? "" : "s")"
        return " (\(([items] + detailParts).joined(separator: ", ")))"
    }

    private var detailParts: [String] {
        var parts: [String] = []
        if let pointsText { parts.append("\(pointsText) pts") }
        if completed > 0 { parts.append("\(completed) done") }
        return parts
    }
}
