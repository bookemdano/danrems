import SwiftUI

struct ReminderRow: View {
    @Environment(ReminderService.self) private var service
    let item: ReminderItem
    var showDate = false
    var showScheduleInfo = false
    var onComplete: ((String, String, Date?) -> Void)?
    var onUncomplete: (() -> Void)?

    @State private var showNotTodayAlert = false
    @State private var pendingCompletion: PendingCompletion?

    var body: some View {
        HStack(spacing: 12) {
            if onComplete != nil {
                Button {
                    if !item.isCompleted {
                        if !item.isDueToday {
                            showNotTodayAlert = true
                        } else {
                            complete()
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
                        complete(movingToToday: true)
                    }
                    Button("Complete As Is") {
                        complete()
                    }
                    Button("Cancel", role: .cancel) {}
                }
                .sheet(item: $pendingCompletion) { pending in
                    CompletionQuestionsView(pending: pending)
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

                    if item.isFun {
                        Image(systemName: "party.popper.fill")
                            .font(.caption)
                            .foregroundStyle(.pink)
                            .accessibilityLabel("Fun")
                    }

                    let questionCount = item.questions.count
                    if questionCount > 0 {
                        Image(systemName: "questionmark.bubble")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("\(questionCount) question\(questionCount == 1 ? "" : "s")")
                    }

                    if item.recurrenceFrequency != nil {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("Repeating")
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

    /// Completes the reminder once its `#q` questions are answered — or right
    /// away when it has none. The move waits for the answers too, so
    /// cancelling the questions leaves the reminder untouched.
    private func complete(movingToToday: Bool = false) {
        pendingCompletion = PendingCompletion.ask(title: item.title, notes: item.notes) { answers in
            if movingToToday { try? service.moveToToday(identifier: item.id) }
            let nextDate = try? service.completeReminder(identifier: item.id, answers: answers)
            onComplete?(item.id, item.title, nextDate)
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
