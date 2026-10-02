import SwiftUI

/// Shows what a plan from the clipboard would do, before any of it is written.
///
/// A plan arrives from an LLM by way of the clipboard, so it's the one input to
/// the app that nobody has checked. Every edit is listed with its before-and-
/// after, and everything that couldn't be resolved is listed too — a plan that
/// only half-applies is visible as such while Cancel is still an option.
struct PlanPreviewView: View {
    @Environment(\.dismiss) private var dismiss

    let plan: ResolvedPlan
    let onApply: () -> Void

    private var applyLabel: String {
        plan.edits.count == 1 ? "Apply" : "Apply \(plan.edits.count)"
    }

    var body: some View {
        NavigationStack {
            Group {
                if plan.isEmpty {
                    ContentUnavailableView(
                        "Nothing to Change",
                        systemImage: "checkmark.circle",
                        description: Text(plan.problems.isEmpty
                            ? "That plan asks for what your reminders already say."
                            : "None of that plan could be applied — see the details below.")
                    )
                } else {
                    planList
                }
            }
            .navigationTitle("Review Plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(applyLabel) {
                        onApply()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(plan.isEmpty)
                }
            }
        }
    }

    private var planList: some View {
        List {
            if let summary = plan.summary {
                Section {
                    Text(summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                ForEach(plan.edits) { edit in
                    editRow(edit)
                }
            } header: {
                Text("\(plan.edits.count) reminder\(plan.edits.count == 1 ? "" : "s") · \(plan.changeCount) change\(plan.changeCount == 1 ? "" : "s")")
            }

            problemsSection
        }
    }

    @ViewBuilder
    private var problemsSection: some View {
        if !plan.problems.isEmpty {
            Section {
                ForEach(plan.problems) { problem in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(problem.reason)
                            .font(.subheadline)
                        Text(problem.ref)
                            .font(.caption.monospaced())
                            .foregroundStyle(.tertiary)
                    }
                }
            } header: {
                Label("Skipped", systemImage: "exclamationmark.triangle")
            } footer: {
                Text("These are left untouched. Applying the plan still makes every change listed above.")
            }
        }
    }

    private func editRow(_ edit: ResolvedPlan.Edit) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Circle()
                    .fill(edit.item.listColor)
                    .frame(width: 8, height: 8)
                Text(edit.item.title)
                    .font(.body.weight(.medium))
            }

            ForEach(edit.changeLines, id: \.self) { line in
                Text(line)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if let why = edit.why {
                Text(why)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }
}
