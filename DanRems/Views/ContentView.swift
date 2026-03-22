import SwiftUI

struct ContentView: View {
    @Environment(ReminderService.self) private var service
    @State private var showCompleted = false
    @State private var showSearch = false
    @State private var showNewReminder = false
    @State private var completedReminders: [ReminderItem] = []

    private var overdueReminders: [ReminderItem] {
        service.reminders.filter(\.isOverdue)
    }

    private var todayReminders: [ReminderItem] {
        service.reminders.filter { $0.isDueToday && !$0.isOverdue }
    }

    private var groupedOverdue: [(String, [ReminderItem])] {
        Dictionary(grouping: overdueReminders, by: \.listName)
            .sorted { $0.key < $1.key }
    }

    private var groupedToday: [(String, [ReminderItem])] {
        Dictionary(grouping: todayReminders, by: \.listName)
            .sorted { $0.key < $1.key }
    }

    private var groupedCompleted: [(String, [ReminderItem])] {
        Dictionary(grouping: completedReminders, by: \.listName)
            .sorted { $0.key < $1.key }
    }

    var body: some View {
        NavigationStack {
            Group {
                if service.authorizationStatus == .fullAccess {
                    remindersList
                } else if service.authorizationStatus == .notDetermined {
                    ProgressView("Requesting access...")
                } else {
                    ContentUnavailableView(
                        "No Access",
                        systemImage: "lock.shield",
                        description: Text("DanRems needs access to your reminders. Please grant access in Settings.")
                    )
                }
            }
            .navigationTitle("DanRems")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showSearch = true } label: {
                        Label("Search", systemImage: "magnifyingglass")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showNewReminder = true } label: {
                        Label("New Reminder", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showSearch) {
                SearchView()
            }
            .sheet(isPresented: $showNewReminder) {
                ReminderEditView(mode: .create)
            }
            .task {
                await service.requestAccess()
            }
            .refreshable {
                await service.fetchReminders()
                if showCompleted {
                    completedReminders = await service.fetchCompletedToday()
                }
            }
        }
    }

    private var remindersList: some View {
        List {
            if !overdueReminders.isEmpty {
                ForEach(groupedOverdue, id: \.0) { listName, items in
                    Section("Overdue - \(listName)") {
                        ForEach(items) { item in
                            NavigationLink(value: item) {
                                ReminderRow(item: item)
                            }
                        }
                    }
                }
            }

            ForEach(groupedToday, id: \.0) { listName, items in
                Section("Today - \(listName)") {
                    ForEach(items) { item in
                        NavigationLink(value: item) {
                            ReminderRow(item: item)
                        }
                    }
                }
            }

            Section {
                Toggle("Show Completed", isOn: $showCompleted)
                    .onChange(of: showCompleted) { _, newValue in
                        if newValue {
                            Task { completedReminders = await service.fetchCompletedToday() }
                        } else {
                            completedReminders = []
                        }
                    }
            }

            if showCompleted && !completedReminders.isEmpty {
                ForEach(groupedCompleted, id: \.0) { listName, items in
                    Section("Completed - \(listName)") {
                        ForEach(items) { item in
                            NavigationLink(value: item) {
                                ReminderRow(item: item)
                            }
                        }
                    }
                }
            }
        }
        .navigationDestination(for: ReminderItem.self) { item in
            ReminderDetailView(reminderID: item.id)
        }
        .overlay {
            if service.reminders.isEmpty && !showCompleted {
                ContentUnavailableView(
                    "All Clear",
                    systemImage: "checkmark.circle",
                    description: Text("No reminders due today or overdue.")
                )
            }
        }
    }
}
