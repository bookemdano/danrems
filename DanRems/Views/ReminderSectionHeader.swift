import SwiftUI

/// Section heading with its point total trailing on the right, plus a done
/// count when the group holds completed reminders.
struct ReminderSectionHeader: View {
    let title: String
    let items: [ReminderItem]

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            if let detail = ReminderTally(items).headerDetail {
                Text(detail)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
