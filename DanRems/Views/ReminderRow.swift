import SwiftUI

struct ReminderRow: View {
    @Environment(ReminderService.self) private var service
    let item: ReminderItem

    var body: some View {
        HStack(spacing: 12) {
            Button {
                try? service.toggleComplete(identifier: item.id)
            } label: {
                Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(item.isCompleted ? .gray : .accentColor)
                    .imageScale(.large)
            }
            .buttonStyle(.plain)

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
                }

                if let dueDate = item.dueDate {
                    Text(dueDate, style: .date)
                        .font(.caption)
                        .foregroundStyle(item.isOverdue ? .red : .secondary)
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
