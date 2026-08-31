import Foundation

/// Effort estimate for a reminder, on a Fibonacci-style scale. The scale is a
/// convention, not a constraint — any value from 0.1 to 100 is accepted.
///
/// EventKit exposes no custom fields on `EKReminder`, so the value rides along
/// as a `#sp<n>` tag inside the notes — the only per-reminder storage that
/// syncs with the reminder itself rather than living on one device. Views read
/// `ReminderItem.displayNotes` so the tag never surfaces as raw text.
struct StoryPoints: Hashable, Comparable, Identifiable, Sendable {
    /// Accepted range. Anything outside it isn't treated as a size tag at all,
    /// so a stray `#sp0` or `#sp500` stays put as ordinary note text.
    static let range: ClosedRange<Double> = 0.1...100

    /// Conventional quick picks — a convenience, not the set of legal values.
    /// The big rungs are off the bar since they never got picked; free entry
    /// still takes any size in `range`.
    static let presets: [StoryPoints] =
        ([0.5, 1, 2, 3, 5, 8] as [Double]).compactMap(StoryPoints.init)

    let value: Double

    var id: Double { value }

    init?(_ value: Double) {
        // Two decimals keeps float noise out of the tag we write back.
        let rounded = (value * 100).rounded() / 100
        guard Self.range.contains(rounded) else { return nil }
        self.value = rounded
    }

    /// "3", "2.5", "0.1" — no trailing zeros, and never localized, since this
    /// same text is what goes into the notes tag.
    var label: String { String(format: "%g", value) }

    static func < (lhs: StoryPoints, rhs: StoryPoints) -> Bool { lhs.value < rhs.value }
}

extension StoryPoints {
    /// `#sp` followed by a number: `#sp5`, `#sp2.5`, `#sp.1`, `#sp100`.
    ///
    /// The trailing lookahead is what stops `#sp1000` from matching as `100`
    /// and `#sp2.5` from matching as just `2`.
    ///
    /// Computed rather than stored: `Regex` isn't `Sendable`, so a static
    /// constant trips Swift 6's global-state check.
    private static var tagPattern: Regex<(Substring, Substring)> {
        /(?i)#sp(\d{1,3}(?:\.\d+)?|\.\d+)(?![\d.])/
    }

    static func parse(from notes: String?) -> StoryPoints? {
        guard let notes else { return nil }
        for match in notes.matches(of: tagPattern) {
            if let points = points(from: match.1) { return points }
        }
        return nil
    }

    /// The note text with every size tag removed, or nil if nothing remains.
    static func strippingTags(from notes: String?) -> String? {
        guard let notes else { return nil }
        let cleaned = notes
            .replacing(tagPattern) { match in
                // Out-of-range near-misses are left alone — they're just text.
                points(from: match.1) == nil ? String(match.0) : ""
            }
            .replacing(/[ \t]{2,}/, with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : cleaned
    }

    /// Rebuilds a notes string from user-authored text plus a size, keeping the
    /// tag on its own trailing line.
    static func encode(notes: String?, points: StoryPoints?) -> String? {
        let body = strippingTags(from: notes)
        guard let points else { return body }
        guard let body else { return "#sp\(points.label)" }
        return "\(body)\n#sp\(points.label)"
    }

    private static func points(from text: Substring) -> StoryPoints? {
        guard let value = Double(text) else { return nil }
        return StoryPoints(value)
    }
}
