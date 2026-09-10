import SwiftUI

/// Date picker sheet for moving one or more reminders to an arbitrary date, and
/// for any other one-date choice — the wording is the caller's to set.
struct PickDateView: View {
    @Environment(\.dismiss) private var dismiss

    let count: Int
    var title: String?
    var actionLabel = "Move"
    var initialDate = Date().startOfDay
    let onPick: (Date) -> Void

    /// Optional so `initialDate` can seed it: `@State` can't be initialized
    /// from another property, so the picker falls back until the user taps.
    @State private var date: Date?

    private var defaultTitle: String {
        count == 1 ? "Move Reminder" : "Move \(count) Reminders"
    }

    var body: some View {
        NavigationStack {
            VStack {
                DatePicker(
                    "Date",
                    selection: Binding(get: { date ?? initialDate }, set: { date = $0 }),
                    displayedComponents: [.date]
                )
                    .datePickerStyle(.graphical)
                    .padding(.horizontal)
                Spacer()
            }
            .navigationTitle(title ?? defaultTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(actionLabel) {
                        onPick((date ?? initialDate).startOfDay)
                        dismiss()
                    }
                }
            }
        }
    }
}
