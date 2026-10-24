import SwiftUI
import UniformTypeIdentifiers

/// Settings for the OneDrive spreadsheet: where it goes, when it last went
/// out, and a button to send it now.
struct SheetSyncView: View {
    @Environment(ReminderService.self) private var service
    @State private var sync = SheetSync.shared
    /// What the open picker is choosing; one `fileImporter` serves both,
    /// since SwiftUI only honors one of them per view.
    @State private var importing: UTType?
    /// Kept apart from `importing`, which the dismissal can clear before the
    /// completion handler gets to read it.
    @State private var pickingFolder = false
    @State private var newFile: CSVFile?
    @State private var isSyncing = false
    @State private var pickError: String?

    var body: some View {
        Form {
            Section {
                if let name = sync.locationName {
                    if sync.isFileLocation {
                        LabeledContent("File", value: name)
                    } else {
                        LabeledContent("Folder", value: name)
                        LabeledContent("File", value: SheetSync.fileName)
                    }
                }
                Button("Create File…") { createFile() }
                Button("Use Existing File…") { pick(.commaSeparatedText) }
                Button("Choose Folder…") { pick(.folder) }
            } footer: {
                Text("Every reminder with a due date — open or completed — is kept in a CSV that opens in Excel. Create it in OneDrive on one device, then use that same file on the other; both keep it up to date. On iPhone, OneDrive only lets you pick files, not folders.")
            }

            if sync.isConfigured {
                Section {
                    Button {
                        syncNow()
                    } label: {
                        HStack {
                            Text("Sync Now")
                            if isSyncing {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }
                    .disabled(isSyncing)

                    if let lastSynced = sync.lastSynced {
                        LabeledContent("Last Synced") {
                            Text(lastSynced, format: .relative(presentation: .named))
                        }
                    }
                    if let count = sync.lastCount {
                        LabeledContent("Reminders", value: count.formatted())
                    }
                    if let error = sync.lastError {
                        Text(error)
                            .foregroundStyle(.red)
                    }
                } footer: {
                    Text("Syncs whenever DanRems opens, after any change, and when reminders change elsewhere while it's open. To sync when DanRems is closed, add the “Sync Reminders Spreadsheet” action to a Shortcuts automation.")
                }

                Section {
                    Button("Stop Syncing", role: .destructive) {
                        sync.stop()
                    }
                } footer: {
                    Text("Only stops this device. The file already in OneDrive is left as it is.")
                }
            }
        }
        .navigationTitle("Spreadsheet Sync")
        .fileImporter(
            isPresented: Binding(get: { importing != nil }, set: { if !$0 { importing = nil } }),
            allowedContentTypes: [importing ?? .folder]
        ) { result in
            use(result, isFile: !pickingFolder)
        }
        .fileExporter(
            isPresented: Binding(get: { newFile != nil }, set: { if !$0 { newFile = nil } }),
            document: newFile,
            contentType: .commaSeparatedText,
            defaultFilename: SheetSync.fileName
        ) { result in
            use(result, isFile: true)
        }
        .alert("Couldn't Use That Location", isPresented: Binding(
            get: { pickError != nil },
            set: { if !$0 { pickError = nil } }
        )) {
            Button("OK") {}
        } message: {
            Text(pickError ?? "")
        }
    }

    private func pick(_ type: UTType) {
        pickingFolder = type == .folder
        importing = type
    }

    private func use(_ result: Result<URL, Error>, isFile: Bool) {
        do {
            try sync.choose(result.get(), isFile: isFile)
            syncNow()
        } catch {
            pickError = error.localizedDescription
        }
    }

    /// Seeds the save dialog with the sheet as it stands, so the new file is
    /// complete the moment it lands rather than waiting for the first sync.
    private func createFile() {
        Task { newFile = CSVFile(data: await sync.currentCSV(using: service)) }
    }

    /// Failures show up through `sync.lastError`, so there's nothing to catch
    /// here beyond keeping the spinner honest.
    private func syncNow() {
        isSyncing = true
        Task {
            _ = try? await sync.syncNow(using: service)
            isSyncing = false
        }
    }
}

/// The spreadsheet as a document, for handing to the save dialog.
private struct CSVFile: FileDocument {
    static let readableContentTypes: [UTType] = [.commaSeparatedText]

    let data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
