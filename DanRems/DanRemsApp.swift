import SwiftUI

@main
struct DanRemsApp: App {
    @State private var reminderService = ReminderService()
// todo Save inprogress in the note field and clear when the item is complete so it isn't set on the new recuring reminder.
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(reminderService)
        }
    }
}
