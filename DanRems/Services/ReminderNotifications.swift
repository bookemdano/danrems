import Foundation
import UserNotifications

/// Local notifications for the reminders that matter — High priority (!!!)
/// only, so the rest stay quiet:
///
///   - Due-time alert: at the due time of a timed reminder. Skipped when the
///     reminder has an alert of its own in Apple Reminders, which would fire
///     as well.
///   - Overdue nudge: one notification each evening listing the High
///     priority reminders due that day or earlier that are still open.
///
/// Notifications have to be booked ahead, since the app isn't running when
/// they fire, so `reschedule` rebuilds them all from scratch on every reload.
/// A reminder finished in Apple Reminders while DanRems sits in the
/// background can therefore still nudge once; the next refresh clears it.
enum ReminderNotifications {
    /// When the overdue nudge goes off, as an hour of the day.
    static let nudgeHour = 19
    /// How many days of nudges and due-time alerts are booked ahead.
    static let lookaheadDays = 7

    private static let duePrefix = "danrems.due."
    private static let nudgePrefix = "danrems.nudge."
    /// iOS keeps at most 64 pending requests; leave room for the nudges.
    private static let maxDueAlerts = 50

    /// The `userInfo` key holding the reminder a notification is about.
    static let reminderIDKey = "reminderID"

    /// Whether a notification is one of ours, rather than e.g. the
    /// "Reminder Deleted" one.
    static func isScheduled(_ identifier: String) -> Bool {
        identifier.hasPrefix(duePrefix) || identifier.hasPrefix(nudgePrefix)
    }

    /// Replaces every pending alert and nudge with ones built from `open`,
    /// the incomplete reminders due through the lookahead window.
    static func reschedule(open: [ReminderItem], now: Date = Date()) async {
        let center = UNUserNotificationCenter.current()
        let pending = await withCheckedContinuation { (continuation: CheckedContinuation<[String], Never>) in
            center.getPendingNotificationRequests { requests in
                continuation.resume(returning: requests.map(\.identifier))
            }
        }
        center.removePendingNotificationRequests(withIdentifiers: pending.filter(isScheduled))

        let important = open
            .filter { $0.isHighPriority && !$0.isCompleted && $0.dueDate != nil }
            .sorted { $0.dueDate! < $1.dueDate! }
        for request in dueAlerts(for: important, now: now) + nudges(for: important, now: now) {
            // Fails only when notifications are off, which leaves nothing to do.
            try? await center.add(request)
        }
    }

    // MARK: - Building requests

    private static func dueAlerts(for items: [ReminderItem], now: Date) -> [UNNotificationRequest] {
        items
            .filter { item in
                guard let due = item.dueDate else { return false }
                return item.hasDueTime && !item.hasAlarms && due > now
            }
            .prefix(maxDueAlerts)
            .map { item in
                let content = UNMutableNotificationContent()
                content.title = item.title
                content.body = "Due now · \(item.listName)"
                content.sound = .default
                content.userInfo = [reminderIDKey: item.id]
                return request(id: duePrefix + item.id, content: content, at: item.dueDate!)
            }
    }

    /// One per evening in the window that has something due by then. Overdue
    /// reminders count toward every evening until they're done, since that's
    /// what the nudge is for.
    private static func nudges(for items: [ReminderItem], now: Date) -> [UNNotificationRequest] {
        let calendar = Calendar.current
        return (0..<lookaheadDays).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: now.startOfDay),
                  let fireAt = calendar.date(bySettingHour: nudgeHour, minute: 0, second: 0, of: day),
                  fireAt > now
            else { return nil }

            let endOfDay = day.endOfDay
            let stillOpen = items.filter { $0.dueDate! <= endOfDay }
            guard let first = stillOpen.first else { return nil }

            let content = UNMutableNotificationContent()
            if stillOpen.count == 1 {
                content.title = "Still open: \(first.title)"
                content.body = first.dueDate! < day ? "Overdue since \(dayLabel(first.dueDate!))" : "Due today"
            } else {
                content.title = "\(stillOpen.count) important reminders still open"
                content.body = stillOpen.map(\.title).joined(separator: " · ")
            }
            content.sound = .default
            // A single reminder opens straight to it; several open the list.
            if stillOpen.count == 1 {
                content.userInfo = [reminderIDKey: first.id]
            }
            let comps = calendar.dateComponents([.year, .month, .day], from: day)
            let id = nudgePrefix + "\(comps.year ?? 0)-\(comps.month ?? 0)-\(comps.day ?? 0)"
            return request(id: id, content: content, at: fireAt)
        }
    }

    private static func request(id: String, content: UNNotificationContent, at date: Date) -> UNNotificationRequest {
        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        return UNNotificationRequest(identifier: id, content: content, trigger: trigger)
    }

    private static func dayLabel(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.abbreviated).month(.defaultDigits).day())
    }
}

/// Receives taps on DanRems's notifications and shows its own alerts while
/// the app is open. The tapped reminder lands in `openReminderID`, where
/// `ContentView` picks it up and navigates to it.
@MainActor
@Observable
final class NotificationRouter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationRouter()

    var openReminderID: String?

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let id = response.notification.request.content.userInfo[ReminderNotifications.reminderIDKey] as? String
        guard let id else { return }
        await MainActor.run { self.openReminderID = id }
    }

    /// iOS hides notifications while the app is in front unless asked; a
    /// due-time alert is worth showing anyway. Anything else keeps the
    /// default of not appearing.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        ReminderNotifications.isScheduled(notification.request.identifier) ? [.banner, .list, .sound] : []
    }
}
