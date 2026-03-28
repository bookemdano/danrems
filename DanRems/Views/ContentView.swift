import SwiftUI

struct ContentView: View {
    @Environment(ReminderService.self) private var service
    @State private var showCompleted = false
    @State private var showUpcoming = false
    @State private var upcomingDays = 3
    @State private var showSearch = false
    @State private var showNewReminder = false
    @State private var completedReminders: [ReminderItem] = []
    @State private var upcomingReminders: [ReminderItem] = []
    @State private var todayOrder: [String] = UserDefaults.standard.stringArray(forKey: "todayOrder") ?? []
    @State private var inProgressIDs: Set<String> = Set(UserDefaults.standard.stringArray(forKey: "inProgressIDs") ?? [])
    @State private var toastMessage: String?

    private var overdueReminders: [ReminderItem] {
        service.reminders.filter(\.isOverdue)
    }

    private var orderedTodayReminders: [ReminderItem] {
        let today = service.reminders.filter { $0.isDueToday && !$0.isOverdue }
        let idSet = Set(today.map(\.id))
        let validOrder = todayOrder.filter { idSet.contains($0) }
        let newItems = today.filter { !validOrder.contains($0.id) }.map(\.id)
        let fullOrder = validOrder + newItems
        return fullOrder.compactMap { id in today.first { $0.id == id } }
    }

    private var groupedOverdue: [(String, [ReminderItem])] {
        Dictionary(grouping: overdueReminders, by: \.listName)
            .sorted { $0.key < $1.key }
    }

    private var groupedCompleted: [(String, [ReminderItem])] {
        Dictionary(grouping: completedReminders, by: \.listName)
            .sorted { $0.key < $1.key }
    }

    private var groupedUpcoming: [(String, [(String, [ReminderItem])])] {
        let byDay = Dictionary(grouping: upcomingReminders) { item -> String in
            guard let date = item.dueDate else { return "No Date" }
            return date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
        }
        return byDay.sorted { a, b in
            let dateA = a.value.compactMap(\.dueDate).min() ?? .distantFuture
            let dateB = b.value.compactMap(\.dueDate).min() ?? .distantFuture
            return dateA < dateB
        }.map { dayLabel, items in
            let byList = Dictionary(grouping: items, by: \.listName)
                .sorted { $0.key < $1.key }
            return (dayLabel, byList)
        }
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
                syncTodayOrder()
            }
            .refreshable {
                await service.fetchReminders()
                syncTodayOrder()
                if showCompleted {
                    completedReminders = await service.fetchCompletedToday()
                }
                if showUpcoming {
                    upcomingReminders = await service.fetchUpcoming(days: upcomingDays)
                }
            }
        }
    }

    private func syncTodayOrder() {
        let today = service.reminders.filter { $0.isDueToday && !$0.isOverdue }
        let idSet = Set(today.map(\.id))
        let validOrder = todayOrder.filter { idSet.contains($0) }
        let newItems = today.filter { !validOrder.contains($0.id) }.map(\.id)
        todayOrder = validOrder + newItems
        saveTodayOrder()
    }

    private func saveTodayOrder() {
        UserDefaults.standard.set(todayOrder, forKey: "todayOrder")
    }

    private func handleComplete(_ title: String, _ nextDate: Date?) {
        if let nextDate {
            showToast("\(title) — next due \(nextDate.formatted(.dateTime.month(.abbreviated).day().year()))")
        } else {
            showToast("\(title) completed")
        }
    }

    private func showToast(_ message: String) {
        toastMessage = message
        Task {
            try? await Task.sleep(for: .seconds(2.5))
            toastMessage = nil
        }
    }

    private func toggleInProgress(_ id: String) {
        if inProgressIDs.contains(id) {
            inProgressIDs.remove(id)
        } else {
            inProgressIDs.insert(id)
        }
        UserDefaults.standard.set(Array(inProgressIDs), forKey: "inProgressIDs")
    }

    private var remindersList: some View {
        List {
            if !overdueReminders.isEmpty {
                Section {
                    Button("Move All to Today") {
                        try? service.moveOverdueToToday()
                    }
                }
                ForEach(groupedOverdue, id: \.0) { listName, items in
                    Section("Overdue - \(listName)") {
                        ForEach(items) { item in
                            NavigationLink(value: item) {
                                ReminderRow(item: item, onComplete: handleComplete)
                            }
                        }
                    }
                }
            }

            Section("Today") {
                ForEach(orderedTodayReminders) { item in
                    NavigationLink(value: item) {
                        HStack {
                            ReminderRow(item: item, onComplete: handleComplete)
                            Spacer()
                            if inProgressIDs.contains(item.id) {
                                Image(systemName: "hammer.fill")
                                    .foregroundStyle(.orange)
                                    .imageScale(.small)
                            }
                            if item.listName != "Reminders" {
                                Text(item.listName)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .swipeActions(edge: .leading) {
                        Button {
                            toggleInProgress(item.id)
                        } label: {
                            Label(
                                inProgressIDs.contains(item.id) ? "Not Started" : "In Progress",
                                systemImage: inProgressIDs.contains(item.id) ? "stop.fill" : "hammer.fill"
                            )
                        }
                        .tint(.orange)
                    }
                }
                .onMove { from, to in
                    todayOrder.move(fromOffsets: from, toOffset: to)
                    saveTodayOrder()
                }
            }

            Section {
                Toggle("Show Upcoming", isOn: $showUpcoming)
                    .onChange(of: showUpcoming) { _, newValue in
                        if newValue {
                            Task { upcomingReminders = await service.fetchUpcoming(days: upcomingDays) }
                        } else {
                            upcomingReminders = []
                        }
                    }
                if showUpcoming {
                    Stepper("Next \(upcomingDays) days", value: $upcomingDays, in: 1...30)
                        .onChange(of: upcomingDays) { _, _ in
                            Task { upcomingReminders = await service.fetchUpcoming(days: upcomingDays) }
                        }
                }
            }

            if showUpcoming && !upcomingReminders.isEmpty {
                ForEach(groupedUpcoming, id: \.0) { dayLabel, listGroups in
                    ForEach(listGroups, id: \.0) { listName, items in
                        Section("\(dayLabel) - \(listName)") {
                            ForEach(items) { item in
                                NavigationLink(value: item) {
                                    ReminderRow(item: item, onComplete: handleComplete)
                                }
                            }
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
                                ReminderRow(item: item, onComplete: handleComplete)
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
            if service.reminders.isEmpty && !showCompleted && !showUpcoming {
                ContentUnavailableView(
                    "All Clear",
                    systemImage: "checkmark.circle",
                    description: Text("No reminders due today or overdue.")
                )
            }
        }
        .overlay(alignment: .bottom) {
            if let toastMessage {
                Text(toastMessage)
                    .font(.subheadline)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.thinMaterial, in: Capsule())
                    .shadow(radius: 4)
                    .padding(.bottom, 32)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut, value: toastMessage)
    }
}
