import SwiftUI
import UIKit

/// Identifies which reminders a presented date picker will move.
struct PickDateTargets: Identifiable {
    let id = UUID()
    let ids: [String]
    var endsSelection = false
}

/// A transient bottom banner. When `reminderID` is set the banner is tappable
/// and opens that reminder's detail page.
struct Toast: Equatable {
    let id = UUID()
    let message: String
    var reminderID: String?
}

/// Navigation value for pushing a detail page by identifier, for reminders we
/// only know by ID (a just-completed item is no longer in the loaded list).
struct ReminderDestination: Hashable {
    let id: String
}

struct ContentView: View {
    @Environment(ReminderService.self) private var service
    @Environment(\.scenePhase) private var scenePhase
    @State private var showCompleted = false
    @State private var showUpcoming = false
    @State private var upcomingDays = 3
    @State private var showSearch = false
    @State private var showNewReminder = false
    @State private var completedReminders: [ReminderItem] = []
    @State private var upcomingReminders: [ReminderItem] = []
    @State private var todayOrder: [String] = UserDefaults.standard.stringArray(forKey: "todayOrder") ?? []
    @State private var toast: Toast?
    @State private var navPath = NavigationPath()
    @State private var isSelecting = false
    @State private var selectedIDs: Set<String> = []
    @State private var pickDateTargets: PickDateTargets?
    /// Gates the foreground refresh: `scenePhase` reaches `.active` during
    /// launch too, and that first load is `.task`'s job.
    @State private var didInitialLoad = false
    /// A plan read off the clipboard, waiting for the user to approve it.
    @State private var pendingPlan: ResolvedPlan?
    @State private var planError: String?

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

    /// The Markdown that Share and Copy both hand out — reminders as displayed,
    /// plus the contract telling the model what plan JSON to send back.
    private var exportText: String {
        ReminderExport.markdown(
            groups: exportGroups,
            listNames: service.calendars.map(\.title).sorted()
        )
    }

    // MARK: - Date shortcuts

    private var tomorrow: Date {
        Calendar.current.date(byAdding: .day, value: 1, to: Date().startOfDay)!
    }

    /// Saturday of the coming weekend (a week out when today is Saturday).
    private var nextSaturday: Date {
        let cal = Calendar.current
        let today = Date().startOfDay
        let weekday = cal.component(.weekday, from: today)
        let daysToSat = ((7 - weekday) % 7 == 0) ? 7 : (7 - weekday)
        return cal.date(byAdding: .day, value: daysToSat, to: today)!
    }

    private var nextSunday: Date {
        Calendar.current.date(byAdding: .day, value: 1, to: nextSaturday)!
    }

    /// Saturday or Sunday of the coming weekend, per the current roll.
    private var nextWeekend: Date {
        menuRolls.weekendIsSunday ? nextSunday : nextSaturday
    }

    /// A weekday (Mon–Fri) in the next seven days, per the current roll. Any
    /// seven consecutive days hold exactly five, so the index always lands.
    private var randomNextWeek: Date {
        let cal = Calendar.current
        let today = Date().startOfDay
        let weekdays = (1...7).compactMap { offset -> Date? in
            let day = cal.date(byAdding: .day, value: offset, to: today)!
            return cal.isDateInWeekend(day) ? nil : day
        }
        return weekdays[menuRolls.weekdayIndex % weekdays.count]
    }

    /// SwiftUI evaluates a `.contextMenu` closure when the row renders, not
    /// when the menu opens, so `Bool.random()` inside it would stick until
    /// something else redrew the row. Keeping the roll in state and bumping it
    /// as the pointer enters a row gives each right-click a fresh menu.
    private struct MenuRolls: Equatable {
        var weekendIsSunday = Bool.random()
        var weekdayIndex = Int.random(in: 0..<5)
    }
    @State private var menuRolls = MenuRolls()

    private func rerollMenuDates() {
        menuRolls = MenuRolls()
    }
    
    private var nextWeek: Date {
        let cal = Calendar.current
        let today = Date().startOfDay
        let weekday = cal.component(.weekday, from: today)
        // On a Monday the modulo lands on 0, which would "move" the item to
        // today — always jump the whole week instead.
        let offset = (9 - weekday) % 7
        let daysToNextMonday = offset == 0 ? 7 : offset
        return cal.date(byAdding: .day, value: daysToNextMonday, to: today)!
    }
    
    /// The 1st of next month, or the month after when that 1st is less than
    /// a week away — late in a month "Next Month" should still be a real jump
    /// rather than landing beside "Next Week".
    private var nextMonth: Date {
        let cal = Calendar.current
        let today = Date().startOfDay
        var comps = cal.dateComponents([.year, .month], from: today)
        comps.month = (comps.month ?? 1) + 1
        comps.day = 1
        let first = cal.date(from: comps)!
        let days = cal.dateComponents([.day], from: today, to: first).day ?? 0
        return days < 7 ? cal.date(byAdding: .month, value: 1, to: first)! : first
    }

    var body: some View {
        NavigationStack(path: $navPath) {
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
                            item: exportText,
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
                // Its own item rather than a third button inside the group
                // above: Mac Catalyst renders only the first two of that group,
                // so a third one silently vanishes from the Mac build while
                // looking fine on iOS.
                ToolbarItem(placement: .topBarLeading) {
                    if !isSelecting {
                        Button { pastePlan() } label: {
                            Label("Paste Plan", systemImage: "text.badge.checkmark")
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
                        Button("Weekend") { rescheduleSelected(to: nextWeekend) }
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
            .sheet(item: $pendingPlan) { plan in
                PlanPreviewView(plan: plan) { apply(plan) }
            }
            .alert("Couldn't Read That Plan", isPresented: Binding(
                get: { planError != nil },
                set: { if !$0 { planError = nil } }
            )) {
                Button("OK") {}
            } message: {
                Text(planError ?? "")
            }
            .sheet(item: $pickDateTargets) { targets in
                PickDateView(count: targets.ids.count) { date in
                    move(targets.ids, to: date)
                    if targets.endsSelection {
                        selectedIDs = []
                        isSelecting = false
                    }
                }
            }
            .task {
                // Before the first load, so that load's reload is what writes
                // the spreadsheet on launch.
                SheetSync.shared.attach(to: service)
                await service.requestAccess()
                syncTodayOrder()
                didInitialLoad = true
            }
            .refreshable { await refreshAll() }
            .onChange(of: scenePhase) { _, phase in
                // What's on screen was fetched before we were suspended: Apple
                // Reminders may have moved on, and if the day rolled over while
                // we were away, "today" and "overdue" mean something different
                // now.
                if phase == .background {
                    flushSheetSync()
                    return
                }
                guard phase == .active, didInitialLoad else { return }
                Task { await refreshAll() }
            }
        }
    }

    // MARK: - Actions

    /// Reloads the main list plus whichever optional sections are showing.
    private func refreshAll() async {
        await service.refresh()
        syncTodayOrder()
        if showCompleted {
            completedReminders = await service.fetchCompletedToday()
        }
        if showUpcoming {
            upcomingReminders = await service.fetchUpcoming(days: upcomingDays)
        }
    }

    /// Writes any spreadsheet sync still waiting out its delay, under a
    /// background task so iOS gives it time to finish before suspending us.
    private func flushSheetSync() {
        let app = UIApplication.shared
        let taskID = app.beginBackgroundTask(withName: "SheetSync", expirationHandler: nil)
        Task {
            await SheetSync.shared.flush()
            app.endBackgroundTask(taskID)
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

    private func handleComplete(_ id: String, _ title: String, _ nextDate: Date?) {
        // completeReminder clears the #wip tag itself, so there's nothing to
        // reset here — the next occurrence comes back not-started.
        if let nextDate {
            showToast("\(title) — next due \(nextDate.formatted(.dateTime.month(.abbreviated).day().year()))",
                      reminderID: id)
        } else {
            showToast("\(title) completed", reminderID: id)
        }
    }

    private func showToast(_ message: String, reminderID: String? = nil) {
        let new = Toast(message: message, reminderID: reminderID)
        toast = new
        Task {
            try? await Task.sleep(for: .seconds(2.5))
            // Leave a newer toast alone; only this one's timer may clear it.
            if toast?.id == new.id { toast = nil }
        }
    }

    @ViewBuilder
    private func toastLabel(_ message: String, tappable: Bool) -> some View {
        HStack(spacing: 6) {
            Text(message)
            if tappable {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .font(.subheadline)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.thinMaterial, in: Capsule())
        .shadow(radius: 4)
    }

    private func toggleSelection(_ id: String) {
        if selectedIDs.contains(id) { selectedIDs.remove(id) } else { selectedIDs.insert(id) }
    }

    private func copyDisplayedReminders() {
        let count = ReminderExport.itemCount(in: exportGroups)
        UIPasteboard.general.string = exportText
        showToast(count == 0
            ? "Nothing to copy"
            : "Copied \(count) reminder\(count == 1 ? "" : "s")")
    }

    /// Reads a plan off the clipboard and opens it for review. Resolution needs
    /// a fresh fetch — the plan may name a reminder that isn't in any section
    /// currently on screen.
    private func pastePlan() {
        let text = UIPasteboard.general.string
        Task {
            do {
                let parsed = try ReminderPlan.parse(text)
                let candidates = await service.fetchPlanCandidates()
                pendingPlan = ResolvedPlan.resolve(
                    parsed,
                    candidates: candidates,
                    calendars: service.calendars
                )
            } catch {
                planError = error.localizedDescription
            }
        }
    }

    /// Anything the plan moved to another day may have crossed into or out of
    /// the Upcoming window, which is fetched separately and won't update itself.
    private func apply(_ plan: ResolvedPlan) {
        do {
            let applied = try service.apply(plan)
            showToast(applied == 0
                ? "Nothing changed"
                : "Updated \(applied) reminder\(applied == 1 ? "" : "s")")
            if showUpcoming {
                Task { upcomingReminders = await service.fetchUpcoming(days: upcomingDays) }
            }
        } catch {
            planError = error.localizedDescription
        }
    }

    /// Moving an item can move it into or out of the Upcoming window, which is
    /// fetched separately from `service.reminders` and so won't update itself.
    private func move(_ ids: [String], to date: Date) {
        do {
            try service.reschedule(identifiers: ids, to: date)
        } catch {
            showToast("Couldn't move: \(error.localizedDescription)")
            return
        }
        showMovedToast(ids, to: date)
        guard showUpcoming else { return }
        Task { upcomingReminders = await service.fetchUpcoming(days: upcomingDays) }
    }

    /// Same shape as the completion toast: one item names the reminder and
    /// opens it on tap; several just report the count.
    private func showMovedToast(_ ids: [String], to date: Date) {
        let when = date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        if ids.count == 1, let id = ids.first {
            let title = (service.reminders + upcomingReminders + completedReminders)
                .first { $0.id == id }?.title ?? "Reminder"
            showToast("\(title) — moved to \(when)", reminderID: id)
        } else {
            showToast("\(ids.count) reminders moved to \(when)")
        }
    }

    private func rescheduleSelected(to date: Date) {
        move(Array(selectedIDs), to: date)
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
            .onHover { if $0 { rerollMenuDates() } }
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
            .onHover { if $0 { rerollMenuDates() } }
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

    /// The move shortcuts in the order they land on the calendar, which
    /// changes with the day of the week (on a Saturday "Next Week" is Monday
    /// but "Next Weekend" is a week away).
    private var dateShortcuts: [(label: String, date: Date)] {
        let weekend = nextWeekend
        return [
            (moveLabel("Today", Date().startOfDay), Date().startOfDay),
            (moveLabel("Tomorrow", tomorrow), tomorrow),
            (moveLabel("Next Weekend", weekend), weekend),
            (moveLabel("Next Monday", nextWeek), nextWeek),
            (moveLabel("Next Month", nextMonth), nextMonth),
        ].sorted { $0.date < $1.date }
    }

    @ViewBuilder
    private func dateContextMenu(for item: ReminderItem) -> some View {
        ForEach(dateShortcuts, id: \.label) { shortcut in
            Button(shortcut.label) { move([item.id], to: shortcut.date) }
        }
        // Kept out of the sorted group so it always sits just above Pick Date.
        let random = randomNextWeek
        Button(moveLabel("Random Next Week", random)) { move([item.id], to: random) }
        Button("Pick Date...") { pickDateTargets = PickDateTargets(ids: [item.id]) }
    }

    /// "Next Week (Mon 10/27)" — the shortcut plus the day it lands on.
    private func moveLabel(_ name: String, _ date: Date) -> String {
        "\(name) (\(monthDay(date)))"
    }

    private static let menuDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE M/d"
        return f
    }()

    /// "Fri 10/24"
    private func monthDay(_ date: Date) -> String {
        Self.menuDateFormatter.string(from: date)
    }

    // MARK: - List

    private var remindersList: some View {
        List {
            if !overdueReminders.isEmpty {
                if !isSelecting {
                    Section {
                        Button("Move All to Today") {
                            let count = overdueReminders.count
                            try? service.moveOverdueToToday()
                            showToast(count == 1 ? "1 reminder moved to today" : "\(count) reminders moved to today")
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
                                .contextMenu { dateContextMenu(for: item) }
            .onHover { if $0 { rerollMenuDates() } }
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

            Section {
                NavigationLink {
                    SheetSyncView()
                } label: {
                    Label("Spreadsheet Sync", systemImage: "tablecells")
                }
            }
        }
        .navigationDestination(for: ReminderItem.self) { item in
            ReminderDetailView(reminderID: item.id)
        }
        .navigationDestination(for: ReminderDestination.self) { destination in
            ReminderDetailView(reminderID: destination.id)
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
            if let toast {
                Group {
                    if let reminderID = toast.reminderID {
                        Button {
                            self.toast = nil
                            navPath.append(ReminderDestination(id: reminderID))
                        } label: {
                            toastLabel(toast.message, tappable: true)
                        }
                        .buttonStyle(.plain)
                    } else {
                        toastLabel(toast.message, tappable: false)
                    }
                }
                .padding(.bottom, 32)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut, value: toast)
    }
}
