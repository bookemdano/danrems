import SwiftUI
import UIKit

/// Identifies which reminders a presented date picker will move.
struct PickDateTargets: Identifiable {
    let id = UUID()
    let ids: [String]
    var endsSelection = false
}

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
    @State private var toastMessage: String?
    @State private var isSelecting = false
    @State private var selectedIDs: Set<String> = []
    @State private var pickDateTargets: PickDateTargets?

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

    /// The on-screen sections, in display order — including Upcoming and
    /// Completed only while they're actually shown, so the export matches what
    /// the user is looking at.
    private var exportGroups: [ReminderExport.Group] {
        var groups = groupedOverdue.map {
            ReminderExport.Group(title: "Overdue — \($0.0)", items: $0.1)
        }
        groups.append(ReminderExport.Group(title: "Today", items: orderedTodayReminders))
        if showUpcoming {
            for (dayLabel, listGroups) in groupedUpcoming {
                for (listName, items) in listGroups {
                    groups.append(ReminderExport.Group(title: "Upcoming — \(dayLabel) — \(listName)", items: items))
                }
            }
        }
        if showCompleted {
            groups.append(contentsOf: groupedCompleted.map {
                ReminderExport.Group(title: "Completed Today — \($0.0)", items: $0.1)
            })
        }
        return groups
    }

    // MARK: - Date shortcuts

    private var tomorrow: Date {
        Calendar.current.date(byAdding: .day, value: 1, to: Date().startOfDay)!
    }

    private var thisWeekend: Date {
        let cal = Calendar.current
        let today = Date().startOfDay
        let weekday = cal.component(.weekday, from: today)
        let daysToSat = ((7 - weekday) % 7 == 0) ? 7 : (7 - weekday)
        return cal.date(byAdding: .day, value: daysToSat, to: today)!
    }

    private var nextMonth: Date {
        let cal = Calendar.current
        var comps = cal.dateComponents([.year, .month], from: Date())
        comps.month = (comps.month ?? 1) + 1
        comps.day = 1
        return cal.date(from: comps)!
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
            .navigationTitle(isSelecting && !selectedIDs.isEmpty ? "\(selectedIDs.count) Selected" : "DanRems")
            .toolbar {
                ToolbarItemGroup(placement: .topBarLeading) {
                    if !isSelecting {
                        Button { showSearch = true } label: {
                            Label("Search", systemImage: "magnifyingglass")
                        }
                        ShareLink(
                            item: ReminderExport.markdown(groups: exportGroups),
                            subject: Text("DanRems reminders")
                        ) {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                        // The share sheet offers Copy too; this is the one-tap path.
                        .contextMenu {
                            Button { copyDisplayedReminders() } label: {
                                Label("Copy to Clipboard", systemImage: "doc.on.doc")
                            }
                        }
                    }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if !isSelecting {
                        Button { showNewReminder = true } label: {
                            Label("New Reminder", systemImage: "plus")
                        }
                    }
                    Button(isSelecting ? "Cancel" : "Select") {
                        isSelecting.toggle()
                        if !isSelecting { selectedIDs = [] }
                    }
                }
                if isSelecting {
                    ToolbarItemGroup(placement: .bottomBar) {
                        Button("Today") { rescheduleSelected(to: Date().startOfDay) }
                            .disabled(selectedIDs.isEmpty)
                        Spacer()
                        Button("Tomorrow") { rescheduleSelected(to: tomorrow) }
                            .disabled(selectedIDs.isEmpty)
                        Spacer()
                        Button("Weekend") { rescheduleSelected(to: thisWeekend) }
                            .disabled(selectedIDs.isEmpty)
                        Spacer()
                        Button("Next Month") { rescheduleSelected(to: nextMonth) }
                            .disabled(selectedIDs.isEmpty)
                        Spacer()
                        Button {
                            pickDateTargets = PickDateTargets(ids: Array(selectedIDs), endsSelection: true)
                        } label: {
                            Label("Pick Date", systemImage: "calendar")
                        }
                        .disabled(selectedIDs.isEmpty)
                    }
                }
            }
            .sheet(isPresented: $showSearch) {
                SearchView()
            }
            .sheet(isPresented: $showNewReminder) {
                ReminderEditView(mode: .create)
            }
            .sheet(item: $pickDateTargets) { targets in
                PickDateView(count: targets.ids.count) { date in
                    try? service.reschedule(identifiers: targets.ids, to: date)
                    if targets.endsSelection {
                        selectedIDs = []
                        isSelecting = false
                    }
                }
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

    // MARK: - Actions

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

    private func handleComplete(_ id: String, _ title: String, _ nextDate: Date?) {
        // completeReminder clears the #wip tag itself, so there's nothing to
        // reset here — the next occurrence comes back not-started.
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

    private func toggleSelection(_ id: String) {
        if selectedIDs.contains(id) { selectedIDs.remove(id) } else { selectedIDs.insert(id) }
    }

    private func copyDisplayedReminders() {
        let groups = exportGroups
        let count = ReminderExport.itemCount(in: groups)
        UIPasteboard.general.string = ReminderExport.markdown(groups: groups)
        showToast(count == 0
            ? "Nothing to copy"
            : "Copied \(count) reminder\(count == 1 ? "" : "s")")
    }

    private func rescheduleSelected(to date: Date) {
        try? service.reschedule(identifiers: Array(selectedIDs), to: date)
        selectedIDs = []
        isSelecting = false
    }

    // MARK: - Row builders

    @ViewBuilder
    private func overdueRow(for item: ReminderItem) -> some View {
        if isSelecting {
            Button { toggleSelection(item.id) } label: {
                selectableContent(for: item)
            }
            .buttonStyle(.plain)
        } else {
            NavigationLink(value: item) {
                ReminderRow(item: item, onComplete: handleComplete)
            }
            .contextMenu { dateContextMenu(for: item) }
        }
    }

    @ViewBuilder
    private func todayRow(for item: ReminderItem) -> some View {
        if isSelecting {
            Button { toggleSelection(item.id) } label: {
                selectableContent(for: item, showExtras: true)
            }
            .buttonStyle(.plain)
        } else {
            NavigationLink(value: item) {
                HStack {
                    ReminderRow(item: item, onComplete: handleComplete)
                    Spacer()
                    if item.isInProgress {
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
            .contextMenu { dateContextMenu(for: item) }
        }
    }

    private func checkbox(checked: Bool) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 5)
                .fill(checked ? Color.accentColor : Color.clear)
            RoundedRectangle(cornerRadius: 5)
                .stroke(checked ? Color.accentColor : Color.secondary, lineWidth: 1.5)
            if checked {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: 22, height: 22)
    }

    private func selectableContent(for item: ReminderItem, showExtras: Bool = false) -> some View {
        HStack {
            checkbox(checked: selectedIDs.contains(item.id))
            ReminderRow(item: item)
            Spacer()
            if showExtras {
                if item.isInProgress {
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
    }

    @ViewBuilder
    private func dateContextMenu(for item: ReminderItem) -> some View {
        Button("Move to Today") { try? service.reschedule(identifiers: [item.id], to: Date().startOfDay) }
        Button("Move to Tomorrow") { try? service.reschedule(identifiers: [item.id], to: tomorrow) }
        Button("Move to This Weekend") { try? service.reschedule(identifiers: [item.id], to: thisWeekend) }
        Button("Move to Next Month") { try? service.reschedule(identifiers: [item.id], to: nextMonth) }
        Button("Pick Date...") { pickDateTargets = PickDateTargets(ids: [item.id]) }
    }

    // MARK: - List

    private var remindersList: some View {
        List {
            if !overdueReminders.isEmpty {
                if !isSelecting {
                    Section {
                        Button("Move All to Today") {
                            try? service.moveOverdueToToday()
                        }
                    }
                }
                ForEach(groupedOverdue, id: \.0) { listName, items in
                    Section {
                        ForEach(items) { item in
                            overdueRow(for: item)
                        }
                    } header: {
                        ReminderSectionHeader(title: "Overdue - \(listName)", items: items)
                    }
                }
            }

            Section {
                if isSelecting {
                    ForEach(orderedTodayReminders) { item in
                        todayRow(for: item)
                    }
                } else {
                    ForEach(orderedTodayReminders) { item in
                        todayRow(for: item)
                    }
                    .onMove { from, to in
                        todayOrder.move(fromOffsets: from, toOffset: to)
                        saveTodayOrder()
                    }
                }
            } header: {
                ReminderSectionHeader(title: "Today", items: orderedTodayReminders)
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
                        Section {
                            ForEach(items) { item in
                                NavigationLink(value: item) {
                                    ReminderRow(item: item, onComplete: handleComplete)
                                }
                            }
                        } header: {
                            ReminderSectionHeader(title: "\(dayLabel) - \(listName)", items: items)
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
                    Section {
                        ForEach(items) { item in
                            NavigationLink(value: item) {
                                ReminderRow(item: item, onComplete: handleComplete, onUncomplete: {
                                    Task { completedReminders = await service.fetchCompletedToday() }
                                })
                            }
                        }
                    } header: {
                        ReminderSectionHeader(title: "Completed - \(listName)", items: items)
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
