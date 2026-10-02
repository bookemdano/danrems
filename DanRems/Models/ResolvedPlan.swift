import EventKit
import Foundation

/// A parsed plan matched against the reminders and lists that actually exist.
///
/// This is the gate between "some JSON was on the clipboard" and "these edits
/// will be written": every handle has to resolve to a real reminder, every list
/// name to a list that already exists, every size to the legal range. Anything
/// that doesn't becomes a `Problem` the preview shows rather than a silent drop,
/// so a plan that half-applied is visible as such before Apply is tapped.
///
/// Changes that ask for what the reminder already has are dropped too, which
/// keeps the preview honest about what tapping Apply will actually do.
struct ResolvedPlan: Identifiable {
    /// Fresh per paste, so presenting the review sheet twice for the same plan
    /// still reopens it.
    let id = UUID()

    /// One reminder and the changes to make to it. Fields left nil are the ones
    /// the plan didn't ask about — `ReminderService.apply` leaves those alone
    /// rather than resetting them to a default.
    struct Edit: Identifiable {
        let item: ReminderItem
        var due: Date? = nil
        var points: StoryPoints? = nil
        var wip: Bool? = nil
        var fun: Bool? = nil
        var list: EKCalendar? = nil
        var why: String? = nil

        var id: String { item.id }

        var isEmpty: Bool {
            due == nil && points == nil && wip == nil && fun == nil && list == nil
        }

        /// One line per change, for the preview.
        var changeLines: [String] {
            var lines: [String] = []
            if let due {
                let day = Date.FormatStyle.dateTime.weekday(.abbreviated).month(.abbreviated).day()
                if let current = item.dueDate {
                    lines.append("Due \(current.formatted(day)) → \(due.formatted(day))")
                } else {
                    lines.append("Due → \(due.formatted(day))")
                }
            }
            if let points {
                if let current = item.storyPoints {
                    lines.append("Size \(current.label) → \(points.label) pts")
                } else {
                    lines.append("Size → \(points.label) pts")
                }
            }
            if let wip { lines.append(wip ? "Mark in progress" : "Clear in progress") }
            if let fun { lines.append(fun ? "Mark fun" : "Clear fun") }
            if let list { lines.append("List → \(list.title)") }
            return lines
        }
    }

    /// Something the plan asked for that can't be done, named so the user can
    /// see what was skipped instead of wondering why nothing happened.
    struct Problem: Identifiable {
        let id = UUID()
        let ref: String
        let reason: String
    }

    var summary: String?
    var edits: [Edit]
    var problems: [Problem]

    var isEmpty: Bool { edits.isEmpty }

    var changeCount: Int { edits.reduce(0) { $0 + $1.changeLines.count } }

    static func resolve(
        _ plan: ReminderPlan,
        candidates: [ReminderItem],
        calendars: [EKCalendar]
    ) -> ResolvedPlan {
        let byRef = ReminderRef.index(candidates)
        var problems: [Problem] = []

        // Group by reminder, keeping first-mentioned order. Several entries for
        // one reminder are merged rather than refused: a model asked for a flat
        // list will sometimes emit one entry per kind of change, and it plainly
        // means all of them.
        var order: [String] = []
        var grouped: [String: [ReminderPlan.Change]] = [:]
        for change in plan.changes {
            let key = ReminderRef.normalizedKey(change.ref)
            guard byRef[key] != nil else {
                problems.append(Problem(
                    ref: displayRef(change.ref),
                    reason: "No reminder with that handle — it may have been completed or deleted."
                ))
                continue
            }
            if grouped[key] == nil { order.append(key) }
            grouped[key, default: []].append(change)
        }

        var edits: [Edit] = []
        for key in order {
            guard let item = byRef[key], let changes = grouped[key] else { continue }
            var edit = Edit(item: item)
            for change in changes {
                fold(change, into: &edit, calendars: calendars, problems: &problems)
            }
            // Everything asked for was already true — nothing to show or write.
            if !edit.isEmpty { edits.append(edit) }
        }

        return ResolvedPlan(summary: plan.summary?.trimmedNonEmpty, edits: edits, problems: problems)
    }

    /// Folds one entry into the edit being built for its reminder.
    ///
    /// Two rules do the work here. A field asking for what the reminder already
    /// has is dropped, so the preview only ever lists real changes. And two
    /// entries setting the *same* field to different values are a genuine
    /// contradiction in the plan — the first wins and the clash is reported,
    /// rather than letting whichever came last quietly decide.
    private static func fold(
        _ change: ReminderPlan.Change,
        into edit: inout Edit,
        calendars: [EKCalendar],
        problems: inout [Problem]
    ) {
        let item = edit.item
        let ref = displayRef(change.ref)

        func skip(_ reason: String) {
            problems.append(Problem(ref: ref, reason: "\(item.title) — \(reason)"))
        }
        func clash(_ field: String) {
            skip("\"\(field)\" was given twice with different values; kept the first.")
        }

        if let raw = change.due {
            if let due = change.dueDate {
                if item.dueDate?.startOfDay != due {
                    if let existing = edit.due, existing != due { clash("due") } else { edit.due = due }
                }
            } else {
                skip("couldn't read the date \"\(raw)\"; expected YYYY-MM-DD.")
            }
        }

        if let raw = change.points {
            if let points = StoryPoints(raw) {
                if item.storyPoints != points {
                    if let existing = edit.points, existing != points { clash("points") } else { edit.points = points }
                }
            } else {
                skip("\(String(format: "%g", raw)) points is outside 0.1–100.")
            }
        }

        if let wip = change.wip, wip != item.isInProgress {
            if let existing = edit.wip, existing != wip { clash("wip") } else { edit.wip = wip }
        }

        if let fun = change.fun, fun != item.isFun {
            if let existing = edit.fun, existing != fun { clash("fun") } else { edit.fun = fun }
        }

        if let name = change.list?.trimmedNonEmpty {
            if let calendar = calendars.first(where: { $0.title.caseInsensitiveCompare(name) == .orderedSame }) {
                if calendar.calendarIdentifier != item.listIdentifier {
                    if let existing = edit.list, existing.calendarIdentifier != calendar.calendarIdentifier {
                        clash("list")
                    } else {
                        edit.list = calendar
                    }
                }
            } else {
                skip("no list named \"\(name)\". Lists aren't created from a plan.")
            }
        }

        edit.why = edit.why ?? change.why?.trimmedNonEmpty
    }

    /// The handle as the model wrote it, for problem messages — trimmed, but not
    /// normalized, so the user can match it against the reply they pasted.
    private static func displayRef(_ raw: String) -> String {
        raw.trimmedNonEmpty ?? raw
    }
}

extension String {
    /// Nil rather than an empty or whitespace-only string, so optional text can
    /// be treated as absent when a model sends `""`.
    var trimmedNonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
