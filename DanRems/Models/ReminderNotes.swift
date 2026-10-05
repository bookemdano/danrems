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
///   - `#q <question>?` — asked on completion, answers logged as `10/1 25mg`
///
/// One type owns them all so that stripping and encoding can't disagree about
/// what counts as a tag. Editors read `ReminderItem.editableNotes` and labels
/// `ReminderItem.displayNotes`, so the raw tags never surface as text.
///
/// Questions are the exception to the trailing tag line: they're free text, so
/// they stay wherever Dan typed them, survive `encode`, and show in editors —
/// there's no other UI to change or remove one.
enum ReminderNotes {
    /// Computed rather than stored: `Regex` isn't `Sendable`, so a static
    /// constant trips Swift 6's global-state check.
    private static var inProgressPattern: Regex<Substring> { /(?i)#wip\b/ }

    private static var funPattern: Regex<Substring> { /(?i)#fun\b/ }

    /// `#q` and a question running to its `?`, so several can share a line:
    /// `#q Dose? #q Site?`. The required space keeps `#quick` from matching.
    private static var questionPattern: Regex<(Substring, Substring)> { /(?i)#q[ \t]+([^?\n]*\?)/ }

    /// `10/1 25mg, left arm` — a logged set of answers.
    private static var logPattern: Regex<(Substring, Substring)> { /^\d{1,2}\/\d{1,2}[ \t]+(.+)$/ }

    /// Stands in for a blank answer when others were given, so the commas
    /// still line up with the questions.
    private static let skippedAnswer = "-"

    static func isInProgress(_ notes: String?) -> Bool {
        guard let notes else { return false }
        return notes.firstMatch(of: inProgressPattern) != nil
    }

    static func isFun(_ notes: String?) -> Bool {
        guard let notes else { return false }
        return notes.firstMatch(of: funPattern) != nil
    }

    /// The questions to ask on completion, in the order they appear.
    static func questions(in notes: String?) -> [String] {
        guard let notes else { return [] }
        return notes.matches(of: questionPattern)
            .map { $0.1.trimmingCharacters(in: .whitespaces) }
            .filter { $0 != "?" }
    }

    /// The user-authored text, with every tag except `#q` removed — what an
    /// editor shows.
    static func strippingTags(from notes: String?) -> String? {
        guard let notes else { return nil }
        // StoryPoints strips last so its whitespace cleanup runs after ours.
        let cleaned = notes
            .replacing(inProgressPattern, with: "")
            .replacing(funPattern, with: "")
        return StoryPoints.strippingTags(from: cleaned)
    }

    /// `strippingTags`, then the questions too — what a label shows. Lines left
    /// empty by the removal go with it.
    static func strippingTagsAndQuestions(from notes: String?) -> String? {
        guard let notes = strippingTags(from: notes) else { return nil }
        let cleaned = notes
            .split(separator: "\n", omittingEmptySubsequences: false)
            .compactMap { line -> String? in
                guard line.firstMatch(of: questionPattern) != nil else { return String(line) }
                let rest = line.replacing(questionPattern, with: "")
                    .replacing(/[ \t]{2,}/, with: " ")
                    .trimmingCharacters(in: .whitespaces)
                return rest.isEmpty ? nil : rest
            }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : cleaned
    }

    /// The log line for one completion — `10/1 25mg, left arm` — or nil when
    /// every answer was left blank.
    static func logEntry(answers: [String], on date: Date) -> String? {
        let trimmed = answers.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard trimmed.contains(where: { !$0.isEmpty }) else { return nil }
        let comps = Calendar.current.dateComponents([.month, .day], from: date)
        let day = "\(comps.month ?? 0)/\(comps.day ?? 0)"
        let text = trimmed.map { $0.isEmpty ? skippedAnswer : $0 }.joined(separator: ", ")
        return "\(day) \(text)"
    }

    /// Adds a log line to the end of the text, above any trailing run of
    /// question-only lines and the tag line, so the history reads oldest
    /// first with the questions underneath.
    static func appendingLog(_ entry: String, to notes: String?) -> String? {
        var lines = strippingTags(from: notes)
            .map { $0.components(separatedBy: "\n") } ?? []
        var insertAt = lines.count
        while insertAt > 0, isQuestionOnly(lines[insertAt - 1]) { insertAt -= 1 }
        lines.insert(entry, at: insertAt)
        return encode(
            notes: lines.joined(separator: "\n"),
            points: StoryPoints.parse(from: notes),
            inProgress: isInProgress(notes),
            isFun: isFun(notes)
        )
    }

    /// The answers from the most recent log line, one per question — a hint
    /// for the next prompt. Splitting on commas is a guess, so a line that
    /// doesn't split into exactly `count` parts is only used whole, for a
    /// single question.
    static func lastAnswers(in notes: String?, count: Int) -> [String]? {
        guard let notes else { return nil }
        let lastLog = notes.split(separator: "\n").reversed().lazy
            .compactMap { $0.trimmingCharacters(in: .whitespaces).firstMatch(of: logPattern) }
            .first
        guard let text = lastLog.map({ String($0.1) }) else { return nil }
        let parts = text.components(separatedBy: ", ")
            .map { $0 == skippedAnswer ? "" : $0 }
        if parts.count == count { return parts }
        return count == 1 ? [text] : nil
    }

    private static func isQuestionOnly(_ line: String) -> Bool {
        line.firstMatch(of: questionPattern) != nil
            && line.replacing(questionPattern, with: "").trimmingCharacters(in: .whitespaces).isEmpty
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
