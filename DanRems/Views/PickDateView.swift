import SwiftUI

/// Date picker sheet for moving one or more reminders to an arbitrary date.
struct PickDateView: View {
    @Environment(\.dismiss) private var dismiss

    let count: Int
    let onPick: (Date) -> Void

    @State private var date = Date().startOfDay

    var body: some View {
        NavigationStack {
            VStack {
                DatePicker("Date", selection: $date, displayedComponents: [.date])
                    .datePickerStyle(.graphical)
                    .padding(.horizontal)
                Spacer()
            }
            .navigationTitle(count == 1 ? "Move Reminder" : "Move \(count) Reminders")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Move") {
                        onPick(date.startOfDay)
                        dismiss()
                    }
                }
            }
        }
    }
}
