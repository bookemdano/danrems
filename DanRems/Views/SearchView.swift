import SwiftUI

struct SearchView: View {
    @Environment(ReminderService.self) private var service
    @Environment(\.dismiss) private var dismiss

    @State private var searchText = ""
    @State private var results: [ReminderItem] = []
    @State private var isSearching = false
    @State private var deleteTarget: ReminderItem?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                if results.isEmpty && !searchText.isEmpty && !isSearching {
                    ContentUnavailableView.search(text: searchText)
                }

                ForEach(results) { item in
                    NavigationLink(value: item) {
                        ReminderRow(item: item, showScheduleInfo: true)
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            deleteTarget = item
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
            .navigationTitle("Search")
            .navigationDestination(for: ReminderItem.self) { item in
                ReminderDetailView(reminderID: item.id)
            }
            .searchable(text: $searchText, prompt: "Search all reminders")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task(id: searchText) {
                guard !searchText.isEmpty else {
                    results = []
                    return
                }
                isSearching = true
                // Debounce
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                results = await service.searchReminders(query: searchText)
                isSearching = false
            }
            .confirmationDialog(
                "Delete Reminder",
                isPresented: .init(
                    get: { deleteTarget != nil },
                    set: { if !$0 { deleteTarget = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    if let target = deleteTarget {
                        do {
                            try service.deleteReminder(identifier: target.id)
                            results.removeAll { $0.id == target.id }
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                    }
                }
                Button("Cancel", role: .cancel) { deleteTarget = nil }
            } message: {
                Text("Are you sure you want to delete this reminder? This cannot be undone.")
            }
            .alert("Error", isPresented: .init(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK") { errorMessage = nil }
            } message: {
                if let errorMessage { Text(errorMessage) }
            }
        }
    }
}
