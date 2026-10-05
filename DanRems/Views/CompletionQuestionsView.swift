import SwiftUI

/// A completion waiting on answers to the reminder's `#q` questions. Built only
/// when there's something to ask, so callers can present it with
/// `.sheet(item:)` and otherwise complete straight away.
struct PendingCompletion: Identifiable {
    let id = UUID()
    let title: String
    let questions: [String]
    let lastAnswers: [String]?
    let complete: ([String]) -> Void

    /// Runs `complete` immediately when `notes` holds no questions and returns
    /// nil; otherwise returns the prompt to present.
    static func ask(
        title: String,
        notes: String?,
        complete: @escaping ([String]) -> Void
    ) -> PendingCompletion? {
        let questions = ReminderNotes.questions(in: notes)
        guard !questions.isEmpty else {
            complete([])
            return nil
        }
        return PendingCompletion(
            title: title,
            questions: questions,
            lastAnswers: ReminderNotes.lastAnswers(in: notes, count: questions.count),
            complete: complete
        )
    }
}

/// Asks a reminder's `#q` questions before it's completed. Cancel leaves the
/// reminder open; completing with every field blank logs nothing.
struct CompletionQuestionsView: View {
    @Environment(\.dismiss) private var dismiss

    let pending: PendingCompletion

    @State private var answers: [String]
    @FocusState private var focused: Int?

    init(pending: PendingCompletion) {
        self.pending = pending
        _answers = State(initialValue: Array(repeating: "", count: pending.questions.count))
    }

    var body: some View {
        NavigationStack {
            Form {
                ForEach(pending.questions.indices, id: \.self) { index in
                    Section(pending.questions[index]) {
                        TextField(placeholder(for: index), text: $answers[index])
                            .focused($focused, equals: index)
                            .submitLabel(index == pending.questions.count - 1 ? .done : .next)
                            .onSubmit {
                                if index + 1 < pending.questions.count {
                                    focused = index + 1
                                } else {
                                    finish()
                                }
                            }
                    }
                }
            }
            .navigationTitle(pending.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Complete") { finish() }
                }
            }
            .onAppear { focused = 0 }
        }
        .presentationDetents([.medium, .large])
    }

    private func placeholder(for index: Int) -> String {
        guard let last = pending.lastAnswers?[index], !last.isEmpty else { return "Answer" }
        return "last: \(last)"
    }

    private func finish() {
        // Dismiss first: completing can remove the row presenting this sheet.
        dismiss()
        pending.complete(answers)
    }
}
