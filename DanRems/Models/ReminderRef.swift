import CryptoKit
import Foundation

/// The short handle the Markdown export prints beside each reminder, and that a
/// plan coming back from an LLM uses to say which reminder it means.
///
/// Derived by hashing the reminder's identifier rather than by counting down
/// the page, so the same reminder always gets the same handle. That's what lets
/// the round trip carry no state: the plan stays valid after the app restarts,
/// after a refresh reorders the list, and even if the sections on screen have
/// changed between the export and the paste. The raw identifier stays out of
/// the export, which keeps the bullets short and readable.
enum ReminderRef {
    /// 8 hex characters — 4.3 billion values, so a collision across even a few
    /// thousand reminders is far less likely than the user noticing.
    private static let hexLength = 8

    /// `r-` and then the hex body. The dash isn't decoration: without it a body
    /// beginning in `e` makes the handle read as the word "ref", and a model
    /// that takes "ref" for a label and strips it eats a hex character with it —
    /// unrecoverable, where stripping `r-` leaves the body whole.
    static func ref(for id: String) -> String {
        "r-\(core(for: id))"
    }

    static func ref(for item: ReminderItem) -> String {
        ref(for: item.id)
    }

    /// The hex body of the handle — the part that actually identifies a
    /// reminder, and the key everything matches on.
    private static func core(for id: String) -> String {
        let digest = SHA256.hash(data: Data(id.utf8))
        return digest.prefix(hexLength / 2).map { String(format: "%02x", $0) }.joined()
    }

    /// Reduces whatever the model echoed back to that hex body.
    ///
    /// Matching on the body alone is deliberate. The printed handle is `r` plus
    /// hex, so one whose body starts with `e` reads as the word "ref" — and a
    /// model that decides "ref" is a label rather than part of the value will
    /// helpfully strip it. Dropping every non-hex character sidesteps that, and
    /// takes wrapping parentheses, backticks, quotes and upper case with it.
    ///
    /// The trailing 8 are what count, so a stray `"ref: r1a2b3c4d"` still lands
    /// on the right reminder. Anything that doesn't reduce to 8 hex characters
    /// is returned as-is and will simply fail to match, which `ResolvedPlan`
    /// reports as a skipped change rather than guessing.
    static func normalizedKey(_ raw: String) -> String {
        let hex = raw.lowercased().filter(\.isHexDigit)
        return hex.count >= hexLength ? String(hex.suffix(hexLength)) : hex
    }

    /// Indexes a candidate pool by hex body, for resolving a plan. First entry
    /// wins, which only comes up when the same reminder arrives in two of the
    /// separately fetched sets.
    static func index(_ items: [ReminderItem]) -> [String: ReminderItem] {
        var map: [String: ReminderItem] = [:]
        for item in items {
            let key = core(for: item.id)
            if map[key] == nil { map[key] = item }
        }
        return map
    }
}
