import SwiftUI

/// Form rows for a reminder's size: a free-entry field plus the conventional
/// Fibonacci rungs as quick picks. Renders as two rows in a `Form`.
struct StoryPointsField: View {
    @Binding var selection: StoryPoints?

    @State private var text = ""
    @FocusState private var focused: Bool

    /// Non-empty text that doesn't name a usable size. Shown in red rather than
    /// blocked, and reverted when the field loses focus.
    private var isInvalid: Bool {
        !text.isEmpty && StoryPoints(Double(text) ?? .nan) == nil
    }

    var body: some View {
        LabeledContent("Size") {
            TextField("None", text: $text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .foregroundStyle(isInvalid ? .red : .primary)
                .focused($focused)
                .onChange(of: text) { _, newText in
                    if newText.isEmpty {
                        selection = nil
                    } else if let points = StoryPoints(Double(newText) ?? .nan) {
                        selection = points
                    }
                }
                .onChange(of: focused) { _, isFocused in
                    // Snap back to the committed value, discarding junk input.
                    if !isFocused { text = selection?.label ?? "" }
                }
                // The owning view may load `selection` after this row appears,
                // so mirror it on change as well as on appear.
                .onChange(of: selection) { _, newValue in
                    if !focused { text = newValue?.label ?? "" }
                }
                .onAppear { text = selection?.label ?? "" }
        }

        // `.borderless` matters: with a bordered/automatic style the Form row
        // swallows the click and routes it to the row rather than the chip
        // under the pointer, which is why picking a preset did nothing on Mac.
        HStack(spacing: 8) {
            ForEach(StoryPoints.presets) { preset in
                Button {
                    selection = preset
                    text = preset.label
                } label: {
                    Text(preset.label)
                        .font(.subheadline.weight(.medium))
                        .monospacedDigit()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .foregroundStyle(selection == preset ? Color.white : Color.primary)
                        .background(
                            selection == preset ? Color.accentColor : Color.gray.opacity(0.2),
                            in: Capsule()
                        )
                        .contentShape(Capsule())
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.vertical, 2)
    }
}

/// Compact point count for list rows.
struct StoryPointsBadge: View {
    let points: StoryPoints

    var body: some View {
        Text(points.label)
            .font(.caption2.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.quaternary, in: Capsule())
            .accessibilityLabel("Size \(points.label)")
    }
}
