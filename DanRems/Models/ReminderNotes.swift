import Foundation

/// The tag vocabulary DanRems embeds in a reminder's notes.
///
/// EventKit exposes no custom fields on `EKReminder`, so per-reminder state
/// that has to travel with the reminder — across devices, and across the
/// occurrences of a recurring one — lives as tags in the notes:
///
///   - `#sp<n>` — size, see `StoryPoints`
///   - `#wip`   — started but not finished
///   - `#fun`   — the ones worth looking forward to
///
/// One type owns them all so that stripping and encoding can't disagree about
/// what counts as a tag. Views read `ReminderItem.displayNotes`, so the raw
/// tags never surface as text.
enum ReminderNotes {
    /// Computed rather than stored: `Regex` isn't `Sendable`, so a static
    /// constant trips Swift 6's global-state check.
    private static var inProgressPattern: Regex<Substring> { /(?i)#wip\b/ }

    private static var funPattern: Regex<Substring> { /(?i)#fun\b/ }

    static func isInProgress(_ notes: String?) -> Bool {
        guard let notes else { return false }
        return notes.firstMatch(of: inProgressPattern) != nil
    }

    static func isFun(_ notes: String?) -> Bool {
        guard let notes else { return false }
        return notes.firstMatch(of: funPattern) != nil
    }

    /// The user-authored text, with every tag removed.
    static func strippingTags(from notes: String?) -> String? {
        guard let notes else { return nil }
        // StoryPoints strips last so its whitespace cleanup runs after ours.
        let cleaned = notes
            .replacing(inProgressPattern, with: "")
            .replacing(funPattern, with: "")
        return StoryPoints.strippingTags(from: cleaned)
    }

    /// Rebuilds a notes string from user-authored text plus the current tags,
    /// gathering them onto a single trailing line.
    static func encode(notes: String?, points: StoryPoints?, inProgress: Bool, isFun: Bool) -> String? {
        var tags: [String] = []
        if inProgress { tags.append("#wip") }
        if isFun { tags.append("#fun") }
        if let points { tags.append("#sp\(points.label)") }

        let body = strippingTags(from: notes)
        guard !tags.isEmpty else { return body }
        let tagLine = tags.joined(separator: " ")
        guard let body else { return tagLine }
        return "\(body)\n\(tagLine)"
    }
}
