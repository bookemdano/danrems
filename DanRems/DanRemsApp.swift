import SwiftUI
import UserNotifications

@main
struct DanRemsApp: App {
    @State private var reminderService = ReminderService()

    init() {
        // Set before launch finishes so a tap that launched the app is delivered.
        UNUserNotificationCenter.current().delegate = NotificationRouter.shared
    }

// todo Save inprogress in the note field and clear when the item is complete so it isn't set on the new recuring reminder.
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(reminderService)
        }
    }
}
