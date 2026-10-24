import EventKit
import Foundation

/// Keeps a CSV of every dated reminder in a place the user picked — meant to
/// be OneDrive, so the file follows them to Excel on any device.
///
/// The pick is either a folder, which gets `fileName` written into it, or the
/// spreadsheet file itself. The Mac can pick the OneDrive folder, but on the
/// iPhone OneDrive won't hand a folder to another app — only single files —
/// so there the file is created or chosen directly.
///
/// Nothing here talks to OneDrive: the file is written through the Files
/// provider (iPhone) or the synced `~/Library/CloudStorage` folder (Mac), and
/// the OneDrive app uploads it. The iPhone and the Mac each remember their own
/// pick of the same spreadsheet and both write it. Because the CSV is
/// built purely from the reminders, the two produce identical bytes, and a
/// write that wouldn't change the file is skipped — which keeps OneDrive from
/// minting conflict copies every time both devices open the app.
@MainActor
@Observable
final class SheetSync {
    static let shared = SheetSync()

    nonisolated static let fileName = "DanRems Reminders.csv"

    /// The picked folder's or file's name, for showing which one is in use.
    private(set) var locationName: String?
    /// Whether the pick is the spreadsheet itself rather than its folder.
    private(set) var isFileLocation = false
    private(set) var lastSynced: Date?
    private(set) var lastCount: Int?
    private(set) var lastError: String?

    var isConfigured: Bool { bookmark != nil }

    private var bookmark: Data? {
        didSet { UserDefaults.standard.set(bookmark, forKey: Keys.bookmark) }
    }

    /// The app's own service, for syncs that start on their own — edits,
    /// store changes, leaving the app. Weak: the app owns it.
    @ObservationIgnored private weak var service: ReminderService?
    @ObservationIgnored private var pending: Task<Void, Never>?
    @ObservationIgnored private var current: Task<Int, Error>?

    private enum Keys {
        static let bookmark = "sheetSyncFolderBookmark"
        static let locationName = "sheetSyncFolderName"
        static let isFileLocation = "sheetSyncIsFileLocation"
        static let lastSynced = "sheetSyncLastSynced"
        static let lastCount = "sheetSyncLastCount"
    }

    private init() {
        let defaults = UserDefaults.standard
        bookmark = defaults.data(forKey: Keys.bookmark)
        locationName = defaults.string(forKey: Keys.locationName)
        isFileLocation = defaults.bool(forKey: Keys.isFileLocation)
        lastSynced = defaults.object(forKey: Keys.lastSynced) as? Date
        lastCount = defaults.object(forKey: Keys.lastCount) as? Int
    }

    // MARK: - Setup

    /// Follows the app's service: every reload of its list, and every change
    /// to the reminders database while we're running — including ones made in
    /// Apple Reminders or synced in from another device — queues a sync.
    func attach(to service: ReminderService) {
        guard self.service !== service else { return }
        self.service = service
        service.onRemindersFetched = { [weak self] in self?.schedule() }
        NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.schedule() }
        }
    }

    /// Remembers a folder or file from a picker. The bookmark is what lets us
    /// back into it on later launches, and from Shortcuts without the UI.
    func choose(_ url: URL, isFile: Bool) throws {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        bookmark = try url.bookmarkData(options: Self.bookmarkOptions)
        locationName = url.lastPathComponent
        isFileLocation = isFile
        UserDefaults.standard.set(locationName, forKey: Keys.locationName)
        UserDefaults.standard.set(isFile, forKey: Keys.isFileLocation)
        lastError = nil
    }

    /// The sheet as it would be written right now — for seeding a new file
    /// through the save dialog.
    func currentCSV(using service: ReminderService) async -> Data {
        Self.encode(await service.fetchDatedReminders())
    }

    /// The byte-order mark is what gets Excel to read the file as UTF-8 rather
    /// than mangling every accent and emoji.
    private static func encode(_ items: [ReminderItem]) -> Data {
        Data("\u{FEFF}".utf8) + Data(ReminderCSV.csv(for: items).utf8)
    }

    /// Stops syncing on this device. The file already in OneDrive is left be.
    func stop() {
        pending?.cancel()
        pending = nil
        bookmark = nil
        locationName = nil
        isFileLocation = false
        lastError = nil
        UserDefaults.standard.removeObject(forKey: Keys.locationName)
        UserDefaults.standard.removeObject(forKey: Keys.isFileLocation)
    }

    // MARK: - Syncing

    /// Queues a sync a moment from now. Edits tend to come in bursts — a plan
    /// applied, a handful moved to tomorrow — and each one triggers a reload,
    /// so waiting lets the burst settle into a single write.
    func schedule() {
        guard isConfigured, service != nil else { return }
        pending?.cancel()
        pending = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            pending = nil
            await syncInBackground()
        }
    }

    /// Runs a queued sync right away instead of waiting out the delay — for
    /// when the app is about to be suspended and the delay would never end.
    func flush() async {
        guard let queued = pending else { return }
        queued.cancel()
        pending = nil
        await syncInBackground()
    }

    private func syncInBackground() async {
        guard let service else { return }
        // Failures land in `lastError` for the settings screen; there's no one
        // to show an alert to for a sync nobody asked for.
        _ = try? await syncNow(using: service)
    }

    /// Writes the spreadsheet now and returns how many reminders it holds.
    ///
    /// Syncs never overlap: each waits for the one before it, so two quick
    /// requests can't race to write the file and the later one always reflects
    /// the newer reminders.
    @discardableResult
    func syncNow(using service: ReminderService) async throws -> Int {
        let previous = current
        let task = Task {
            _ = try? await previous?.value
            return try await performSync(using: service)
        }
        current = task
        return try await task.value
    }

    private func performSync(using service: ReminderService) async throws -> Int {
        do {
            guard let bookmark else { throw SheetSyncError.notConfigured }
            // Without access every fetch comes back empty, and writing that
            // would wipe the sheet on the other device's behalf.
            guard EKEventStore.authorizationStatus(for: .reminder) == .fullAccess else {
                throw SheetSyncError.noRemindersAccess
            }

            let location = try resolveLocation(from: bookmark)
            let items = await service.fetchDatedReminders()
            let data = Self.encode(items)

            let isFile = isFileLocation
            try await Task.detached {
                if isFile {
                    try Self.write(data, to: location, scopedBy: location)
                } else {
                    try Self.write(data, to: location.appendingPathComponent(Self.fileName), scopedBy: location)
                }
            }.value

            lastSynced = Date()
            lastCount = items.count
            lastError = nil
            UserDefaults.standard.set(lastSynced, forKey: Keys.lastSynced)
            UserDefaults.standard.set(lastCount, forKey: Keys.lastCount)
            return items.count
        } catch {
            lastError = error.localizedDescription
            throw error
        }
    }

    private func resolveLocation(from bookmark: Data) throws -> URL {
        var isStale = false
        let url: URL
        do {
            url = try URL(
                resolvingBookmarkData: bookmark,
                options: Self.bookmarkResolutionOptions,
                bookmarkDataIsStale: &isStale
            )
        } catch {
            throw SheetSyncError.locationUnavailable
        }
        // A stale bookmark still resolves — it just needs replacing before it
        // stops doing so, which means while we still have access through it.
        if isStale {
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            if let fresh = try? url.bookmarkData(options: Self.bookmarkOptions) {
                self.bookmark = fresh
            }
        }
        return url
    }

    /// Replaces the file unless it already holds exactly `data`.
    ///
    /// The comparison read is coordinated so the file provider fetches the
    /// latest copy first — otherwise a file last written by the other device
    /// would look missing or stale, and we'd rewrite it for nothing.
    ///
    /// `scope` is the bookmarked URL that grants access — the folder, or the
    /// file itself. The write is in place rather than atomic: an atomic write
    /// goes through a temporary file beside the target, and with only the file
    /// granted there's no permission to create one.
    private nonisolated static func write(_ data: Data, to file: URL, scopedBy scope: URL) throws {
        let accessing = scope.startAccessingSecurityScopedResource()
        defer { if accessing { scope.stopAccessingSecurityScopedResource() } }

        let coordinator = NSFileCoordinator()
        var coordinationError: NSError?
        var existing: Data?
        coordinator.coordinate(readingItemAt: file, options: [], error: &coordinationError) { url in
            existing = try? Data(contentsOf: url)
        }
        if existing == data { return }

        var writeError: Error?
        coordinationError = nil
        coordinator.coordinate(writingItemAt: file, options: .forReplacing, error: &coordinationError) { url in
            do {
                try data.write(to: url)
            } catch {
                writeError = error
            }
        }
        if let error = coordinationError ?? writeError { throw error }
    }

    // MARK: - Bookmark options

    /// The Mac's sandbox only honors a bookmark minted with a security scope;
    /// iOS has no such option and scopes bookmarks from the picker on its own.
    private static var bookmarkOptions: URL.BookmarkCreationOptions {
        #if targetEnvironment(macCatalyst)
        [.withSecurityScope]
        #else
        []
        #endif
    }

    private static var bookmarkResolutionOptions: URL.BookmarkResolutionOptions {
        #if targetEnvironment(macCatalyst)
        [.withSecurityScope]
        #else
        []
        #endif
    }
}

enum SheetSyncError: LocalizedError {
    case notConfigured
    case noRemindersAccess
    case locationUnavailable

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            "No spreadsheet is set up. Choose one in DanRems under Spreadsheet Sync."
        case .noRemindersAccess:
            "DanRems doesn't have access to your reminders."
        case .locationUnavailable:
            "The spreadsheet can't be found. Choose it again in DanRems under Spreadsheet Sync."
        }
    }
}
