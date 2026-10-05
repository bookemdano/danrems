import SwiftUI

/// The `#q` questions a reminder asks when it's completed: lists them with
/// the answer each got last time, and adds, edits or removes them. Works on
/// the editor's copy, so changes land with the rest of the form on Save.
struct QuestionsSection: View {
    @Binding var questions: [String]
    /// Last logged answer per question, from `ReminderItem.lastAnswers`.
    var lastAnswers: [String: String] = [:]

    @State private var newQuestion = ""
    /// Left set after the alert closes: SwiftUI may clear `isPresented`
    /// before running the button's action, so the action can't rely on it.
    @State private var editingIndex: Int?
    @State private var showEdit = false
    @State private var editingText = ""
    @FocusState private var addFocused: Bool

    var body: some View {
        Section {
            ForEach(Array(questions.enumerated()), id: \.offset) { index, question in
                Button {
                    editingText = question
                    editingIndex = index
                    showEdit = true
                } label: {
                    row(for: question)
                }
                .buttonStyle(.plain)
            }
            .onDelete { questions.remove(atOffsets: $0) }

            HStack(spacing: 10) {
                Image(systemName: "plus.circle.fill")
                    .foregroundStyle(.tint)
                    .imageScale(.large)
                TextField("Add a question", text: $newQuestion)
                    .focused($addFocused)
                    .submitLabel(.done)
                    .onSubmit(add)
            }
        } header: {
            Text("Questions")
        } footer: {
            Text(questions.isEmpty
                 ? "Questions are asked when you complete this reminder, like \"Dose?\" for a medication."
                 : "Asked when you complete this reminder. Answers are logged in the notes and carried to the next one if it repeats.")
        }
        .alert("Edit Question", isPresented: $showEdit) {
            TextField("Question", text: $editingText)
            Button("Save") { saveEdit() }
            Button("Delete", role: .destructive) { deleteEditing() }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func row(for question: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "questionmark.bubble")
                .foregroundStyle(.tint)
                .imageScale(.large)
            VStack(alignment: .leading, spacing: 2) {
                Text(question)
                    .foregroundStyle(.primary)
                if let last = lastAnswers[question] {
                    Text("Last: \(last)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }

    /// Keeps the field focused so several questions can go in one after another.
    private func add() {
        guard let question = ReminderNotes.normalizedQuestion(newQuestion) else { return }
        questions.append(question)
        newQuestion = ""
        addFocused = true
    }

    /// Clearing the text removes the question, same as Delete.
    private func saveEdit() {
        guard let index = editingIndex, questions.indices.contains(index) else { return }
        if let question = ReminderNotes.normalizedQuestion(editingText) {
            questions[index] = question
        } else {
            questions.remove(at: index)
        }
    }

    private func deleteEditing() {
        guard let index = editingIndex, questions.indices.contains(index) else { return }
        questions.remove(at: index)
    }
}
