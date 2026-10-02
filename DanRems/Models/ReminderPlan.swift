import Foundation

/// A plan handed back by an LLM: what to change about which reminders.
///
/// The wire format is deliberately flat — one entry per reminder, every field
/// but `ref` optional — rather than one array per kind of change. That's the
/// shape a model gets right most often, and it makes the preview a straight
/// list of "this reminder, these changes".
///
/// Nothing here creates, deletes or renames a reminder: a plan can only
/// reschedule, resize, reflag and refile what the export already listed. The
/// contract printed by `ReminderExport` says as much, and `ResolvedPlan` is
/// what enforces it.
struct ReminderPlan: Decodable, Sendable {
    struct Change: Decodable, Sendable {
        let ref: String
        let due: String?
        let points: Double?
        let wip: Bool?
        let fun: Bool?
        let list: String?
        let why: String?
    }

    let summary: String?
    let changes: [Change]
}

// MARK: - Parsing

enum PlanParseError: LocalizedError {
    case clipboardEmpty
    case noJSONFound
    case malformed(String)
    case noChanges

    var errorDescription: String? {
        switch self {
        case .clipboardEmpty:
            "The clipboard is empty. Copy Claude's reply first."
        case .noJSONFound:
            "No JSON found on the clipboard. Copy Claude's whole reply, including the ```json block."
        case .malformed(let detail):
            "That JSON didn't match the plan format: \(detail)"
        case .noChanges:
            "That plan didn't list any changes."
        }
    }
}

extension ReminderPlan {
    /// Pulls a plan out of whatever the user actually copied — a bare JSON
    /// object, a ```json fence, or a fence buried in prose — because asking
    /// someone to trim a reply by hand before pasting it is a good way to make
    /// the feature go unused.
    static func parse(_ raw: String?) throws -> ReminderPlan {
        guard let raw, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PlanParseError.clipboardEmpty
        }
        guard let json = extractJSON(from: raw) else { throw PlanParseError.noJSONFound }

        let data = Data(json.utf8)
        let decoder = JSONDecoder()
        let plan: ReminderPlan
        do {
            plan = try decoder.decode(ReminderPlan.self, from: data)
        } catch {
            // A bare array of changes is the other shape models reach for.
            guard let changes = try? decoder.decode([Change].self, from: data) else {
                throw PlanParseError.malformed(readable(error))
            }
            plan = ReminderPlan(summary: nil, changes: changes)
        }
        guard !plan.changes.isEmpty else { throw PlanParseError.noChanges }
        return plan
    }

    /// The first balanced `{…}` or `[…]` span, ignoring braces inside strings.
    /// Scanning for balance rather than for a fence means a reply that lost its
    /// fence on the way to the clipboard still parses.
    private static func extractJSON(from text: String) -> String? {
        let chars = Array(text)
        guard let start = chars.firstIndex(where: { $0 == "{" || $0 == "[" }) else { return nil }
        let opener = chars[start]
        let closer: Character = opener == "{" ? "}" : "]"

        var depth = 0
        var inString = false
        var escaped = false
        for i in start..<chars.count {
            let c = chars[i]
            if escaped { escaped = false; continue }
            if inString {
                if c == "\\" { escaped = true } else if c == "\"" { inString = false }
                continue
            }
            switch c {
            case "\"": inString = true
            case opener: depth += 1
            case closer:
                depth -= 1
                if depth == 0 { return String(chars[start...i]) }
            default: break
            }
        }
        return nil
    }

    private static func readable(_ error: Error) -> String {
        guard let error = error as? DecodingError else { return error.localizedDescription }
        switch error {
        case .keyNotFound(let key, _):
            return "a change is missing \"\(key.stringValue)\""
        case .typeMismatch(let type, let context):
            let field = context.codingPath.last?.stringValue ?? "a field"
            return "\"\(field)\" should be \(type == Bool.self ? "true or false" : "\(type)")"
        case .valueNotFound(_, let context):
            return "\"\(context.codingPath.last?.stringValue ?? "a field")\" was null"
        case .dataCorrupted(let context):
            return context.debugDescription
        @unknown default:
            return error.localizedDescription
        }
    }
}

extension ReminderPlan.Change {
    /// `due` as a calendar day. Accepts a plain `YYYY-MM-DD` and the front of a
    /// full ISO timestamp, since a model asked for the former often sends the
    /// latter. Time of day is dropped on purpose — `ReminderService.apply`
    /// keeps whatever time the reminder already had.
    var dueDate: Date? {
        guard let due, due.count >= 10 else { return nil }
        let day = String(due.prefix(10))
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: day)?.startOfDay
    }
}
