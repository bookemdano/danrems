import SwiftUI

@main
struct DanRemsApp: App {
    @State private var reminderService = ReminderService()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(reminderService)
        }
    }
}
