import SwiftUI

struct ReminderRow: View {
    @Environment(ReminderService.self) private var service
    let item: ReminderItem
    var showDate = false
    var showScheduleInfo = false
    var onComplete: ((String, String, Date?) -> Void)?
    var onUncomplete: (() -> Void)?

    @State private var showNotTodayAlert = false

    var body: some View {
        HStack(spacing: 12) {
            if onComplete != nil {
                Button {
                    if !item.isCompleted {
                        if !item.isDueToday {
                            showNotTodayAlert = true
                        } else {
                            let nextDate = try? service.completeReminder(identifier: item.id)
                            onComplete?(item.id, item.title, nextDate)
                        }
                    } else {
                        try? service.toggleComplete(identifier: item.id)
                        onUncomplete?()
                    }
                } label: {
                    Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(item.isCompleted ? .gray : .accentColor)
                        .imageScale(.large)
                }
                .buttonStyle(.plain)
                .confirmationDialog("This item isn't due today.", isPresented: $showNotTodayAlert, titleVisibility: .visible) {
                    Button("Move to Today & Complete") {
                        try? service.moveToToday(identifier: item.id)
                        let nextDate = try? service.completeReminder(identifier: item.id)
                        onComplete?(item.id, item.title, nextDate)
                    }
                    Button("Complete Anyway") {
                        let nextDate = try? service.completeReminder(identifier: item.id)
                        onComplete?(item.id, item.title, nextDate)
                    }
                    Button("Cancel", role: .cancel) {}
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    if item.priority > 0 {
                        Text(priorityText)
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    Text(item.title)
                        .strikethrough(item.isCompleted)
                        .foregroundStyle(item.isOverdue ? .red : .primary)

                    if let points = item.storyPoints {
                        StoryPointsBadge(points: points)
                    }
                }

                if showDate, let dueDate = item.dueDate {
                    Text(dueDate, style: .date)
                        .font(.caption)
                        .foregroundStyle(item.isOverdue ? .red : .secondary)
                }

                if showScheduleInfo {
                    if item.isCompleted, let completionDate = item.completionDate {
                        Text("Completed \(completionDate.formatted(.dateTime.month(.abbreviated).day().year()))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if let dueDate = item.dueDate {
                        Text("Due \(dueDate.formatted(.dateTime.month(.abbreviated).day().year()))")
                            .font(.caption)
                            .foregroundStyle(item.isOverdue ? .red : .secondary)
                    }
                }
            }
        }
    }

    private var priorityText: String {
        switch item.priority {
        case 1: "!!!"
        case 5: "!!"
        case 9: "!"
        default: ""
        }
    }
}
