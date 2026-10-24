import AppIntents

/// The Shortcuts action that refreshes the OneDrive spreadsheet without
/// opening DanRems — what a time-of-day automation runs so the sheet stays
/// current on days the app itself never gets opened.
struct SyncSpreadsheetIntent: AppIntent {
    static let title: LocalizedStringResource = "Sync Reminders Spreadsheet"
    static let description = IntentDescription(
        "Updates the DanRems spreadsheet in OneDrive with every reminder that has a due date."
    )

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        // A service of its own rather than the app's: when Shortcuts runs this
        // the UI may never have launched, so there's no app service to borrow.
        let count = try await SheetSync.shared.syncNow(using: ReminderService())
        return .result(dialog: "Synced \(count) reminder\(count == 1 ? "" : "s").")
    }
}

struct DanRemsShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: SyncSpreadsheetIntent(),
            phrases: ["Sync \(.applicationName) spreadsheet"],
            shortTitle: "Sync Spreadsheet",
            systemImageName: "tablecells"
        )
    }
}
